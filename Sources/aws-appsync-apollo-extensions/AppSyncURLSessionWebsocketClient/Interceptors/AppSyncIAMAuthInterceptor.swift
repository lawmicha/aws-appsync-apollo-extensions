import Foundation
import Apollo
import Foundation
import ApolloAPI

public class AppSyncIAMAuthInterceptor: AppSyncInterceptor {

    public var id: String = UUID().uuidString

    let region: String
    let signRequest: (_ urlRequest: URLRequest, _ region: String) async throws -> URLRequest?

    public init(region: String,
                signRequest: @escaping (URLRequest, String) async throws -> URLRequest?) {
        self.region = region
        self.signRequest = signRequest
    }
}

extension AppSyncIAMAuthInterceptor {
    public func interceptConnection(url: URL) async -> URL {
        let connectUrl = appSyncApiEndpoint(url).appendingPathComponent("connect")

        var urlRequest = URLRequest(url: connectUrl)
        // host is in URL
        // path is in URL
        urlRequest.httpMethod = "POST"

        // some headers
        urlRequest.setValue("application/json, text/javascript", forHTTPHeaderField: "accept")
        urlRequest.setValue("amz-1.0", forHTTPHeaderField: "content-encoding")
        urlRequest.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")

        urlRequest.httpBody = Data("{}".utf8)

        guard let signedRequest = try? await signRequest(urlRequest, region) else {
            return connectUrl
        }
        // get host, authToken, securityToken, amzDate back out.

        guard let headers = signedRequest.allHTTPHeaderFields else {
            return connectUrl
        }

        let headersExtracted = headers.reduce([String: String]()) { partialResult, header in
            switch header.key.lowercased() {
            case "authorization", "x-amz-date", "x-amz-security-token":
                return partialResult.merging([header.key.lowercased(): header.value]) { $1 }
            default:
                return partialResult
            }
        }

        return AppSyncRealTimeRequestAuth.URLQuery(
            header: .iam(.init(host: connectUrl.host!,
                               authToken: headersExtracted["authorization"] ?? "",
                               securityToken: headersExtracted["x-amz-security-token"] ?? "",
                               amzDate: headersExtracted["x-amz-date"] ?? ""))
        ).withBaseURL(url)
    }
}

extension AppSyncIAMAuthInterceptor {
    public func interceptRequest(
        event: AppSyncRealTimeRequest,
        url: URL
    ) async -> AppSyncRealTimeRequest {
        guard case .start(let request) = event else {
            return event
        }

        let appSyncUrl = appSyncApiEndpoint(url)
        // remove query parameters set during connection.
        var components = URLComponents(url: appSyncUrl, resolvingAgainstBaseURL: false)!
        components.query = nil

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "POST"

        // some headers
        urlRequest.setValue("application/json, text/javascript", forHTTPHeaderField: "accept")
        urlRequest.setValue("amz-1.0", forHTTPHeaderField: "content-encoding")
        urlRequest.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = Data(request.data.utf8)

        guard let signedRequest = try? await signRequest(urlRequest, region) else {
            return .start(.init(id: request.id,
                                data: request.data, auth: nil))
        }
        // get host, authToken, securityToken, amzDate back out.

        guard let headers = signedRequest.allHTTPHeaderFields else {
            return .start(.init(id: request.id,
                                data: request.data, auth: nil))
        }

        let headersExtracted = headers.reduce([String: String]()) { partialResult, header in
            switch header.key.lowercased() {
            case "authorization", "x-amz-date", "x-amz-security-token":
                return partialResult.merging([header.key.lowercased(): header.value]) { $1 }
            default:
                return partialResult
            }
        }

        return .start(.init(
            id: request.id,
            data: request.data,
            auth: .iam(.init(host: appSyncUrl.host!,
                             authToken: headersExtracted["authorization"] ?? "",
                             securityToken: headersExtracted["x-amz-security-token"] ?? "",
                             amzDate: headersExtracted["x-amz-date"] ?? ""))))
        
    }
}

extension AppSyncIAMAuthInterceptor {

    public func interceptAsync<Operation>(
        chain: RequestChain,
        request: HTTPRequest<Operation>,
        response: HTTPResponse<Operation>?,
        completion: @escaping (Result<GraphQLResult<Operation.Data>, Error>) -> Void
    ) where Operation : ApolloAPI.GraphQLOperation {

        guard let urlRequest = try? request.toURLRequest() else {
            //completion(.failure(APIError.unknown("Could not get urlRequest from request", "")))
            return
        }

        Task {
            let signedRequest = try await signRequest(urlRequest, region)

            signedRequest?.allHTTPHeaderFields?.forEach({ header in
                request.addHeader(name: header.key, value: header.value)
            })
            chain.proceedAsync(
                request: request,
                response: response,
                interceptor: self,
                completion: completion)
        }
    }
}

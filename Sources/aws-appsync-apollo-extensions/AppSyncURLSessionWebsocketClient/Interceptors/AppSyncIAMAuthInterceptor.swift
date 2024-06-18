import Foundation
import Apollo
import Foundation
import ApolloAPI

public class AppSyncIAMAuthInterceptor: AppSyncInterceptor {

    public var id: String = UUID().uuidString

    let region: String
    let signRequest: (URLRequest, String) async throws -> URLRequest?
    let getAuthHeader: (URL, Data, String) async throws -> (String, String, String, String)?

    public init(region: String,
                signRequest: @escaping (URLRequest, String) async throws -> URLRequest?,
                getAuthHeader: @escaping (URL, Data, String) async throws -> (String, String, String, String)?) {
        self.region = region
        self.signRequest = signRequest
        self.getAuthHeader = getAuthHeader
    }
}

extension AppSyncIAMAuthInterceptor {
    public func interceptConnection(url: URL) async -> URL {
        let connectUrl = appSyncApiEndpoint(url).appendingPathComponent("connect")
        guard let authHeader = try? await getAuthHeader(connectUrl, 
                                                        Data("{}".utf8),
                                                        region) else {
            return connectUrl
        }

        return AppSyncRealTimeRequestAuth.URLQuery(
            header: .iam(.init(host: authHeader.0,
                               authToken: authHeader.1,
                               securityToken: authHeader.2,
                               amzDate: authHeader.3))
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
        guard let authHeader = try? await getAuthHeader(
            appSyncApiEndpoint(url),
            Data(request.data.utf8),
            region) else {
            return .start(.init(id: request.id,
                                data: request.data, auth: nil))
        }
        return .start(.init(
            id: request.id,
            data: request.data,
            auth: .iam(.init(host: authHeader.0,
                             authToken: authHeader.1,
                             securityToken: authHeader.2,
                             amzDate: authHeader.3))))

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

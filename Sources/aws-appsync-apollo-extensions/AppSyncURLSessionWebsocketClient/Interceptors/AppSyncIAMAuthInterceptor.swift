import Foundation
import Apollo
import Foundation
import ApolloAPI

public class AppSyncIAMAuthInterceptor: AppSyncInterceptor {

    public var id: String = UUID().uuidString

    let signRequest: (URLRequest) async throws -> URLRequest?
    let getAuthHeader: (URL, Data) async throws -> AppSyncRealTimeRequestAuth.IAM?

    public init(signRequest: @escaping (URLRequest) async throws -> URLRequest?,
                getAuthHeader: @escaping (URL, Data) async throws -> AppSyncRealTimeRequestAuth.IAM?) {
        self.signRequest = signRequest
        self.getAuthHeader = getAuthHeader
    }
}

extension AppSyncIAMAuthInterceptor {
    public func interceptConnection(url: URL) async -> URL {
        let connectUrl = appSyncApiEndpoint(url).appendingPathComponent("connect")
        guard let authHeader = try? await getAuthHeader(connectUrl, Data("{}".utf8)) else {
            return connectUrl
        }

        return AppSyncRealTimeRequestAuth.URLQuery(
            header: .iam(authHeader)
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
        let authHeader = try? await getAuthHeader(
            appSyncApiEndpoint(url),
            Data(request.data.utf8))
        return .start(.init(
            id: request.id,
            data: request.data,
            auth: authHeader.map { .iam($0) }
        ))
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
            let signedRequest = try await signRequest(urlRequest)

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

import Foundation
import Apollo
import ApolloAPI

public class AppSyncAuthTokenInterceptor: AppSyncInterceptor {

    public var id: String = UUID().uuidString

    let getLatestAuthToken: () async throws -> String

    static let AWSDateISO8601DateFormat2 = "yyyyMMdd'T'HHmmss'Z'"


    public init(getLatestAuthToken: @escaping () async throws -> String) {
        self.getLatestAuthToken = getLatestAuthToken
    }

    private func getAuthToken() async -> String {
        // A user that is not signed in should receive an unauthorized error from
        // the connection attempt. This code achieves this by always creating a valid
        // request to AppSync even when the token cannot be retrieved. The request sent
        // to AppSync will receive a response indicating the request is unauthorized.
        // If we do not use empty token string and perform the remaining logic of the
        // request construction then it will fail request validation at AppSync before
        // the authorization check, which ends up being propagated back to the caller
        // as a "bad request". Example of bad requests are when the header and payload
        // query strings are missing or when the data is not base64 encoded.
        (try? await getLatestAuthToken()) ?? ""
    }
}

extension AppSyncAuthTokenInterceptor: ApolloInterceptor {
    public func interceptAsync<Operation>(
        chain: RequestChain,
        request: HTTPRequest<Operation>,
        response: HTTPResponse<Operation>?,
        completion: @escaping (Result<GraphQLResult<Operation.Data>, Error>) -> Void
    ) where Operation : ApolloAPI.GraphQLOperation {

        let date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = Self.AWSDateISO8601DateFormat2
        let amzDate = dateFormatter.string(from: date)

        request.addHeader(name: "X-Amz-Date", value: amzDate)

        Task {
            let token = await getAuthToken()
            request.addHeader(name: "authorization", value: token)
            chain.proceedAsync(
                request: request,
                response: response,
                interceptor: self,
                completion: completion)
        }
    }
}

extension AppSyncAuthTokenInterceptor: WebSocketInterceptor {
    public func interceptConnection(url: URL) async -> URL {
        let authToken = await getAuthToken()

        return AppSyncRealTimeRequestAuth.URLQuery(
            header: .authToken(.init(
                host: appSyncApiEndpoint(url).host!,
                authToken: authToken
            ))
        ).withBaseURL(url)
    }
}

extension AppSyncAuthTokenInterceptor: AppSyncRequestInterceptor {

    public func interceptRequest(event: AppSyncRealTimeRequest, url: URL) async -> AppSyncRealTimeRequest {
        guard case .start(let request) = event else {
            return event
        }

        let authToken = await getAuthToken()

        return .start(.init(
            id: request.id,
            data: request.data,
            auth: .authToken(.init(
                host: appSyncApiEndpoint(url).host!,
                authToken: authToken
            ))
        ))
    }
}

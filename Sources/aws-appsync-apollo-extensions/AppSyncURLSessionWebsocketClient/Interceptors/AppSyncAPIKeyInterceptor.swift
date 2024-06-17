//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//


import Foundation
import ApolloAPI
import Apollo

public class AppSyncAPIKeyInterceptor: AppSyncInterceptor {
    public var id: String = UUID().uuidString

    private let apiKey: String
    private let getAuthHeader = authHeaderBuilder()

    public init(apiKey: String) {
        self.apiKey = apiKey
    }
}

extension AppSyncAPIKeyInterceptor: ApolloInterceptor {
    public func interceptAsync<Operation>(chain: Apollo.RequestChain, request: Apollo.HTTPRequest<Operation>, response: Apollo.HTTPResponse<Operation>?, completion: @escaping (Result<Apollo.GraphQLResult<Operation.Data>, Error>) -> Void) where Operation : ApolloAPI.GraphQLOperation {

        request.addHeader(name: "X-Api-Key", value: apiKey)

        chain.proceedAsync(
            request: request,
            response: response,
            interceptor: self,
            completion: completion)
    }
}
extension AppSyncAPIKeyInterceptor: WebSocketInterceptor {
    public func interceptConnection(url: URL) async -> URL {
        let authHeader = getAuthHeader(apiKey, appSyncApiEndpoint(url).host!)
        return AppSyncRealTimeRequestAuth.URLQuery(
            header: .apiKey(authHeader)
        ).withBaseURL(url)
    }
}

extension AppSyncAPIKeyInterceptor: AppSyncRequestInterceptor {
    public func interceptRequest(event: AppSyncRealTimeRequest, url: URL) async -> AppSyncRealTimeRequest {
        let host = appSyncApiEndpoint(url).host!
        guard case .start(let request) = event else {
            return event
        }
        return .start(.init(
            id: request.id,
            data: request.data,
            auth: .apiKey(getAuthHeader(apiKey, host))
        ))
     }
}

fileprivate func authHeaderBuilder() -> (String, String) -> AppSyncRealTimeRequestAuth.ApiKey {
    let formatter = DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    return { apiKey, host in
        AppSyncRealTimeRequestAuth.ApiKey(
            host: host,
            apiKey: apiKey,
            amzDate: formatter.string(from: Date())
        )
    }

}

func appSyncApiEndpoint(_ url: URL) -> URL {
    guard let host = url.host else {
        return url
    }

    guard host.hasSuffix("amazonaws.com") else {
        if url.lastPathComponent == "realtime" {
            return url.deletingLastPathComponent()
        }
        return url
    }

    guard var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return url
    }

    urlComponents.host = host.replacingOccurrences(of: "appsync-realtime-api", with: "appsync-api")
    guard let apiUrl = urlComponents.url else {
        return url
    }
    return apiUrl
}

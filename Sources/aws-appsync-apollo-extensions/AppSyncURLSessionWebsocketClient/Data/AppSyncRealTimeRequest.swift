//
//  AppSyncRealTimeRequest.swift
//  apollo-test
//
//  Created by Law, Michael on 2024-05-27.
//

import Foundation

public enum AppSyncRealTimeRequest {
    case connectionInit
    case start(StartRequest)
    case stop(String)

    public struct StartRequest {
        public let id: String
        let data: String
        let auth: AppSyncRealTimeRequestAuth?
    }

    public var id: String? {
        switch self {
        case let .start(request): return request.id
        case let .stop(id): return id
        default: return nil
        }
    }
}



extension AppSyncRealTimeRequest: Encodable {
    enum CodingKeys: CodingKey {
        case type
        case payload
        case id
    }

    enum PayloadCodingKeys: CodingKey {
        case data
        case extensions
    }

    enum ExtensionsCodingKeys: CodingKey {
        case authorization
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .connectionInit:
            try container.encode("connection_init", forKey: .type)
        case .start(let startRequest):
            try container.encode("start", forKey: .type)
            try container.encode(startRequest.id, forKey: .id)

            let payloadEncoder = container.superEncoder(forKey: .payload)
            var payloadContainer = payloadEncoder.container(keyedBy: PayloadCodingKeys.self)
            try payloadContainer.encode(startRequest.data, forKey: .data)

            let extensionEncoder = payloadContainer.superEncoder(forKey: .extensions)
            var extensionContainer = extensionEncoder.container(keyedBy: ExtensionsCodingKeys.self)
            try extensionContainer.encodeIfPresent(startRequest.auth, forKey: .authorization)
        case .stop(let id):
            try container.encode("stop", forKey: .type)
            try container.encode(id, forKey: .id)
        }
    }
}

public enum AppSyncRealTimeRequestAuth {
    case authToken(AuthToken)
    case apiKey(ApiKey)
    case iam(IAM)

    public struct AuthToken {
        let host: String
        let authToken: String
    }

    public struct ApiKey {
        let host: String
        let apiKey: String
        let amzDate: String
    }

    public struct IAM {
        let host: String
        let authToken: String
        let securityToken: String
        let amzDate: String
    }

    public struct URLQuery {
        let header: AppSyncRealTimeRequestAuth
        let payload: String

        init(header: AppSyncRealTimeRequestAuth, payload: String = "{}") {
            self.header = header
            self.payload = payload
        }

        func withBaseURL(_ url: URL, encoder: JSONEncoder? = nil) -> URL {
            let jsonEncoder: JSONEncoder = encoder ?? JSONEncoder()
            guard let headerJsonData = try? jsonEncoder.encode(header) else {
                return url
            }

            guard var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else {
                return url
            }

            urlComponents.queryItems = [
                URLQueryItem(name: "header", value: headerJsonData.base64EncodedString()),
                URLQueryItem(name: "payload", value: try? payload.base64EncodedString())
            ]

            return urlComponents.url ?? url
        }
    }
}
extension StringProtocol {
    public func base64EncodedString() throws -> String {
        let utf8Encoded = self.data(using: .utf8)
        guard let base64String = utf8Encoded?.base64EncodedString() else {
            //throw ClientError.serializationFailed("Failed to base64 encode a string")
            return ""
        }
        return base64String
    }
}

extension AppSyncRealTimeRequestAuth: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .apiKey(let apiKey):
            try container.encode(apiKey)
        case .authToken(let cognito):
            try container.encode(cognito)
        case .iam(let iam):
            try container.encode(iam)
        }
    }
}

extension AppSyncRealTimeRequestAuth.AuthToken: Encodable {
    enum CodingKeys: String, CodingKey {
        case host
        case authToken = "Authorization"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encode(authToken, forKey: .authToken)
    }
}

extension AppSyncRealTimeRequestAuth.ApiKey: Encodable {
    enum CodingKeys: String, CodingKey {
        case host
        case apiKey = "x-api-key"
        case amzDate = "x-amz-date"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(amzDate, forKey: .amzDate)
    }
}

extension AppSyncRealTimeRequestAuth.IAM: Encodable {
    enum CodingKeys: String, CodingKey {
        case host
        case accept
        case contentType = "content-type"
        case authToken = "Authorization"
        case securityToken = "X-Amz-Security-Token"
        case contentEncoding = "content-encoding"
        case amzDate = "x-amz-date"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encode("application/json, text/javascript", forKey: .accept)
        try container.encode("application/json; charset=UTF-8", forKey: .contentType)
        try container.encode("amz-1.0", forKey: .contentEncoding)
        try container.encode(securityToken, forKey: .securityToken)
        try container.encode(authToken, forKey: .authToken)
        try container.encode(amzDate, forKey: .amzDate)
    }
}

//////
//////  AWSIAMAuthInterceptor+Apollo.swift
//////  apollo-test
//////
//////  Created by Law, Michael on 2024-05-27.
//////
//
//import Foundation
////import Apollo
////import ApolloAPI
//
//import ClientRuntime
////import AWSPluginsCore
//import AwsCommonRuntimeKit
//
//import Foundation
//
//class AmplifyAppSyncSigV4Signer: AppSyncSigV4Signer {
//
//    let region: String
//    let signer: AmplifyAWSSignatureV4Signer
//
//    init(region: String, signer: AmplifyAWSSignatureV4Signer = AmplifyAWSSignatureV4Signer()) {
//        self.region = region
//        self.signer = signer
//        CommonRuntimeKit.initialize()
//    }
//
//    func signRequest(_ urlRequest: URLRequest) async throws -> URLRequest? {
//        let requestBuilder = try createAppSyncSdkHttpRequestBuilder(
//            urlRequest: urlRequest,
//            headers: urlRequest.allHTTPHeaderFields,
//            body: urlRequest.httpBody)
//
//        guard let sdkHttpRequest = try await signer.sigV4SignedRequest(
//            requestBuilder: requestBuilder,
//            signingName: "appsync",
//            signingRegion: region,
//            date: Date()
//        ) else {
//            //throw APIError.unknown("Unable to sign request", "")
//            return nil
//        }
//
//        return setHeaders(from: sdkHttpRequest, to: urlRequest)
//    }
//
//    func getAuthHeader(_ endpoint: URL, with payload: Data) async throws -> AppSyncRealTimeRequestAuth.IAM? {
//        guard let host = endpoint.host else {
//            return nil
//        }
//
//        /// The process of getting the auth header for an IAM based authentication request is as follows:
//        ///
//        /// 1. A request is created with the IAM based auth headers (date,  accept, content encoding, content type, and
//        /// additional headers.
//        let requestBuilder = SdkHttpRequestBuilder()
//            .withHost(host)
//            .withPath(endpoint.path)
//            .withMethod(.post)
//            .withPort(443)
//            .withProtocol(.https)
//            .withHeader(name: "accept", value: "application/json, text/javascript")
//            .withHeader(name: "content-encoding", value: "amz-1.0")
//            .withHeader(name: "Content-Type", value: "application/json; charset=UTF-8")
//            .withHeader(name: "host", value: host)
//            .withBody(.data(payload))
//
//        /// 2. The request is SigV4 signed by using all the available headers on the request. By signing the request, the signature is added to
//        /// the request headers as authorization and security token.
//        do {
//            guard let urlRequest = try await signer.sigV4SignedRequest(
//                requestBuilder: requestBuilder,
//                signingName: "appsync",
//                signingRegion: region,
//                date: Date()) 
//            else {
//                print("Unable to sign request")
//                return nil
//            }
//
//            // TODO: Using long lived credentials without getting a session with security token will fail
//            // since the session token does not exist on the signed request, and is an empty string.
//            // Once Amplify.Auth is ready to be integrated, this code path needs to be re-tested.
//            let headers = urlRequest.headers.headers.reduce([String: String]()) { partialResult, header in
//                switch header.name.lowercased() {
//                case "authorization", "x-amz-date", "x-amz-security-token":
//                    guard let headerValue = header.value.first else {
//                        return partialResult
//                    }
//                    return partialResult.merging([header.name.lowercased(): headerValue]) { $1 }
//                default:
//                    return partialResult
//                }
//            }
//
//            return .init(
//                host: host,
//                authToken: headers["authorization"] ?? "",
//                securityToken: headers["x-amz-security-token"] ?? "",
//                amzDate: headers["x-amz-date"] ?? ""
//            )
//        } catch {
//            print("Unable to sign request")
//            return nil
//        }
//    }
//
//
//    func setHeaders(from sdkRequest: SdkHttpRequest, to urlRequest: URLRequest) -> URLRequest {
//        var urlRequest = urlRequest
//        for header in sdkRequest.headers.headers {
//            urlRequest.setValue(header.value.joined(separator: ","), forHTTPHeaderField: header.name)
//        }
//        return urlRequest
//    }
//
//    func createAppSyncSdkHttpRequestBuilder(urlRequest: URLRequest,
//                                            headers: [String : String]?,
//                                            body: Data?) throws -> SdkHttpRequestBuilder {
//
//        guard let url = urlRequest.url else {
//            throw "Could not get url from mutable request"
//        }
//        guard let host = url.host else {
//            throw "Could not get host from mutable request"
//        }
//        var headers = urlRequest.allHTTPHeaderFields ?? [:]
//        headers.updateValue(host, forKey: "host")
//
//        let httpMethod = (urlRequest.httpMethod?.uppercased())
//            .flatMap(HttpMethodType.init(rawValue:)) ?? .get
//
//        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
//            .map { ClientRuntime.SDKURLQueryItem(name: $0.name, value: $0.value)} ?? []
//
//        let requestBuilder = SdkHttpRequestBuilder()
//            .withHost(host)
//            .withPath(url.path)
//            .withQueryItems(queryItems)
//            .withMethod(httpMethod)
//            .withPort(443)
//            .withProtocol(.https)
//            .withHeaders(.init(headers))
//            .withBody(.data(urlRequest.httpBody))
//
//        return requestBuilder
//    }
//}
//
//extension String: Error {
//
//}

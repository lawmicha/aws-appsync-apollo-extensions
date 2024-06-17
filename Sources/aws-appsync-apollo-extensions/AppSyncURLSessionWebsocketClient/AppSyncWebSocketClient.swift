//
//  AppSyncWebsocketClient.swift
//  apollo-test
//
//  Created by Law, Michael on 2024-05-24.
//

import Foundation

import Apollo
import ApolloWebSocket
import ApolloAPI
import Combine

public class AppSyncWebSocketClient: NSObject, ApolloWebSocket.WebSocketClient {

    public enum Error: Swift.Error {
        case connectionLost
        case connectionCancelled
    }

    // MARK: - ApolloWebSocket.WebSocketClient

    public var request: URLRequest
    public var delegate: ApolloWebSocket.WebSocketClientDelegate?
    public var callbackQueue: DispatchQueue

    // MARK: - Internal

    /// The underlying URLSessionWebSocketTask
    private var connection: URLSessionWebSocketTask? {
        willSet {
            self.connection?.cancel(with: .goingAway, reason: nil)
        }
    }

    /// Internal wriable WebSocketEvent data stream
    let subject = PassthroughSubject<WebSocketEvent, Never>()
    var cancellable: AnyCancellable?

    public var isConnected: Bool {
        self.connection?.state == .running
    }

    /// Interceptor for appending additional info before makeing the connection
    private var interceptor: AppSyncInterceptor?

    public convenience init(endpointURL: URL,
                            interceptor: AppSyncInterceptor? = nil) {
        self.init(endpointURL: endpointURL, delegate: nil, callbackQueue: .main, interceptor: interceptor)
    }
    init(endpointURL: URL,
         delegate: ApolloWebSocket.WebSocketClientDelegate?,
         callbackQueue: DispatchQueue,
         interceptor: AppSyncInterceptor? = nil) {
        let url = Self.useWebSocketProtocolScheme(url: appSyncRealTimeEndpoint(endpointURL))
        self.request = URLRequest(url: url)
        self.delegate = delegate
        self.callbackQueue = callbackQueue
        self.interceptor = interceptor

        self.request.setValue("graphql-ws", forHTTPHeaderField: "Sec-WebSocket-Protocol")

    }

    public func connect() {
        print("Calling Connect")
        guard self.connection?.state != .running else {
            print("[WebSocketClient] WebSocket is already in connecting state")
            return
        }

        self.cancellable = subject.sink { completion in
            print("Completed")
        } receiveValue: { [weak self] event in
            guard let self else {
                return
            }
            switch event {
            case .connected:
                self.delegate?.websocketDidConnect(socket: self)
            case .data(let data):
                self.delegate?.websocketDidReceiveData(socket: self, data: data)
            case .string(let string):
                self.delegate?.websocketDidReceiveMessage(socket: self, text: string)
            case .disconnected(let closeCode, let string):
                print("Disconnected closeCode \(closeCode), string \(string)")
                // should send back error
                self.delegate?.websocketDidDisconnect(socket: self, error: nil)
            case .error(let error):
                self.delegate?.websocketDidDisconnect(socket: self, error: error)
            }
        }
        Task {
            print("[WebSocketClient] Creating new connection and starting read")
            self.connection = await createWebSocketConnection()
            // Perform reading from a WebSocket in a separate task recursively to avoid blocking the execution.
            Task { await self.startReadMessage() }
            self.connection?.resume()
        }
    }

    public func disconnect(forceTimeout: TimeInterval?) {
        print("Calling Disconnect")
        guard self.connection?.state == .running else {
            print("[WebSocketClient] client should be in connected state to trigger disconnect")
            return
        }

        self.connection?.cancel(with: .goingAway, reason: nil)
    }

    public func write(ping: Data, completion: (() -> Void)?) {
        print("Not called, not implemented.")
    }

    public func write(string: String) {
        Task {
            guard await self.isConnected else {
                print("[AppSyncRealTimeClient] Attempting to write to a webSocket haven't been connected.")
                return
            }

            print("[WebSocketClient] WebSocket write message string: \(string)")

            // first we decode to AppSyncRealTimeRequest.

            // If it can be decoded, then we intercept it.

            guard let json = try? JSONSerialization.jsonObject(with: string.data(using: .utf8)!) as? JSONObject else {
                print("writing not json")
                Task { try await self.connection?.send(.string(string)) }
                return
            }

            guard let id = json["id"] as? String else {
                print("writing not json")
                Task { try await self.connection?.send(.string(string)) }
                return
            }
            let type = json["type"] as? String
            let payload = json["payload"] as? JSONObject

            print("Determining type: ", type)

            // handle "start" case

            guard type == "start" else {
                // not start, still write it - like "connection"
                Task { try await self.connection?.send(.string(string)) }
                return
            }

            // let's intercept the message by extracting out the query.
            guard let query = payload?["query"] else {
                // Could not do anything
                Task { try await self.connection?.send(.string(string)) }
                return
            }

            // Add query
            var dataDict: [String: Any] = ["query": query]
            // Add variables
            if let subVariables = payload?["variables"] {
                dataDict["variables"] = subVariables
            }

            // Turn into JSON
            let jsonData = try! JSONSerialization.data(withJSONObject: dataDict)

            // Create AppSyncMessage
            let event = AppSyncRealTimeRequest.start(.init(
                id: id,
                data: String(decoding: jsonData, as: UTF8.self),
                auth: nil))

            // Intercept the request
            guard let url = self.request.url else {
                print("ERROR")
                return
            }

            guard let interceptedEvent = await self.interceptor?.interceptRequest(event: event,
                                                                                  url: url) else {
                print("ERROR")
                return
            }

            let jsonEncoder = JSONEncoder()
            let encodedjsonData = try! jsonEncoder.encode(interceptedEvent)

            guard let jsonString = String(data: encodedjsonData, encoding: .utf8) else {
                //let jsonError = ConnectionProviderError.jsonParse(signedMessage.id, nil)
                //self.updateCallback(event: .error(jsonError))
                return
            }
            Task { try await self.connection?.send(.string(jsonString)) }

        }
    }

    // MARK: - Deinit

    deinit {
        self.subject.send(completion: .finished)
        self.cancellable = nil
    }

    // MARK: - Connect Internals

    private func createWebSocketConnection() async -> URLSessionWebSocketTask {

        let url = self.request.url!
        let decoratedURL = (await self.interceptor?.interceptConnection(url: url)) ?? url

        request.url = decoratedURL

        let urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        return urlSession.webSocketTask(with: request)
    }

    /**
     Recusively read WebSocket data frames and publish to data stream.
     */
    private func startReadMessage() async {
        guard let connection = self.connection else {
            print("[WebSocketClient] WebSocket connection doesn't exist")
            return
        }

        if connection.state == .canceling || connection.state == .completed {
            print("[WebSocketClient] WebSocket connection state is \(connection.state). Failed to read websocket message")
            return
        }

        do {
            let message = try await connection.receive()
            print("[WebSocketClient] WebSocket received message: \(String(describing: message))")
            switch message {
            case .data(let data):
                subject.send(.data(data))
            case .string(let string):
                subject.send(.string(string))
            @unknown default:
                break
            }
        } catch {
            if connection.state == .running {
                subject.send(.error(error))
            } else {
                print("[WebSocketClient] read message failed with connection state \(connection.state), error \(error)")
            }
        }

        await self.startReadMessage()
    }
}


// MARK: - URLSession delegate

extension AppSyncWebSocketClient: URLSessionWebSocketDelegate {
    
    nonisolated public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        print("[WebSocketClient] Websocket connected")
        self.subject.send(.connected)
    }

    nonisolated public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        print("[WebSocketClient] Websocket disconnected")
        self.subject.send(.disconnected(closeCode, reason.flatMap { String(data: $0, encoding: .utf8) }))
    }

    nonisolated public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Swift.Error?
    ) {
        guard let error else {
            print("[WebSocketClient] URLSession didComplete")
            return
        }

        print("[WebSocketClient] URLSession didCompleteWithError: \(error))")

        let nsError = error as NSError
        switch (nsError.domain, nsError.code) {
        case (NSURLErrorDomain.self, NSURLErrorNetworkConnectionLost), // connection lost
             (NSPOSIXErrorDomain.self, Int(ECONNABORTED)): // background to foreground
            self.subject.send(.error(Error.connectionLost))
        case (NSURLErrorDomain.self, NSURLErrorCancelled):
            print("Skipping NSURLErrorCancelled error")
            self.subject.send(.error(Error.connectionCancelled))
        default:
            self.subject.send(.error(error))
        }
    }
}


enum WebSocketEvent {
    case connected
    case disconnected(URLSessionWebSocketTask.CloseCode, String?)
    case data(Data)
    case string(String)
    case error(Error)
}

extension AppSyncWebSocketClient {
    static func useWebSocketProtocolScheme(url: URL) -> URL {
        guard var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        if urlComponents.scheme == "ws" || urlComponents.scheme == "wss" {
            return url
        }
        urlComponents.scheme = urlComponents.scheme == "http" ? "ws" : "wss"
        return urlComponents.url ?? url
    }
}


func appSyncRealTimeEndpoint(_ url: URL) -> URL {
    guard let host = url.host else {
        return url
    }

    guard host.hasSuffix("amazonaws.com") else {
        return url.appendingPathComponent("realtime")
    }

    guard var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return url
    }

    urlComponents.host = host.replacingOccurrences(of: "appsync-api", with: "appsync-realtime-api")
    guard let realTimeUrl = urlComponents.url else {
        return url
    }

    return realTimeUrl
}


struct AppSyncPayloadContainer {

}

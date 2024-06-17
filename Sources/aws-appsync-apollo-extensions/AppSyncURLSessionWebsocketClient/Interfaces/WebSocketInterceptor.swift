//
//  WebSocketInterceptor.swift
//  apollo-test
//
//  Created by Law, Michael on 2024-05-27.
//

import Foundation

public protocol WebSocketInterceptor {
    func interceptConnection(url: URL) async -> URL
}

//
//  AppSyncRequestInterceptor.swift
//  apollo-test
//
//  Created by Law, Michael on 2024-05-27.
//

import Foundation

public protocol AppSyncRequestInterceptor {
    func interceptRequest(event: AppSyncRealTimeRequest, url: URL) async -> AppSyncRealTimeRequest
}

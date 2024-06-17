//
//  AppSyncInterceptor.swift
//  apollo-test
//
//  Created by Law, Michael on 2024-05-27.
//

import Foundation
import Apollo

public protocol AppSyncInterceptor: WebSocketInterceptor, AppSyncRequestInterceptor, ApolloInterceptor {}

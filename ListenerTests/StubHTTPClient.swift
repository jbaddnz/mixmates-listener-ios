//
//  StubHTTPClient.swift
//  ListenerTests
//
//  Created by jamie baddeley on 11/04/2026.
//

import Foundation
@testable import Listener

/// Test stub for `HTTPClient`. Each test instantiates one with a handler
/// closure that produces the canned `(Data, HTTPURLResponse)` tuple for the
/// requests the test cares about.
///
/// All state is per-instance — there is no shared static, no global mutex,
/// and no parallelism hazard between Swift Testing suites that all stub the
/// network. Each test owns its own client.
struct StubHTTPClient: HTTPClient {
    let handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try handler(request)
    }
}

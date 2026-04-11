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
///
/// **Cancellation parity with real `URLSession`**: this stub honours
/// `Task.isCancelled` and throws `URLError(.cancelled)` before invoking
/// the handler, the same way `URLSession.send` does. Without this check,
/// the stub silently succeeds inside cancelled tasks while real hardware
/// fails — exactly the bug that shipped with the Stop early flow before
/// being caught in hardware verification (the recognition request was
/// running inside the cancelled `recordingTask` and threw `.cancelled`
/// at the URLSession layer).
struct StubHTTPClient: HTTPClient {
    let handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if Task.isCancelled {
            throw URLError(.cancelled)
        }
        return try handler(request)
    }
}

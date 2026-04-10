//
//  HTTPClient.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import Foundation

/// Thin protocol seam between `ListenerAPI` and the underlying HTTP transport.
///
/// Modelled after Apple's `ClientTransport` protocol from `swift-openapi-runtime`
/// (https://github.com/apple/swift-openapi-runtime), adapted to use `URLRequest`
/// and `HTTPURLResponse` directly so that the project can stay true to its
/// no-third-party-dependency rule.
///
/// The seam exists for testability: production wires `URLSession.shared`,
/// tests wire `StubHTTPClient` with a per-instance closure handler. There is
/// no `URLProtocol` subclass anywhere in the test target — a per-instance stub
/// avoids the parallel-suite race conditions that plague the
/// `URLProtocol + static handler` pattern in Swift Testing.
///
/// Apple DTS engineer Quinn endorses this exact shape on the Swift Forums
/// (https://forums.swift.org/t/mock-urlprotocol-with-strict-swift-6-concurrency/77135):
///
/// > "I generally recommend that you introduce an abstraction layer between
/// > your request-response code and your network transport… For many apps
/// > that interface can be as simple as a throwing async function that takes
/// > a URLRequest and returns an HTTPURLResponse."
///
/// The method is named `send(_:)` rather than `data(for:)` so it does not
/// collide with `URLSession.data(for:)` and so the `URLSession` conformance
/// reads cleanly.
protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// `URLSession` conforms by delegating to its built-in `data(for:)` and
/// downcasting the response. Any non-HTTP response — which should never
/// happen for an `https://` endpoint — becomes a `URLError(.badServerResponse)`
/// so callers can treat it as a regular network failure.
extension URLSession: HTTPClient {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await self.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

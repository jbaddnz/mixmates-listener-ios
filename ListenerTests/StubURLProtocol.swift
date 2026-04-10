//
//  StubURLProtocol.swift
//  ListenerTests
//
//  Created by jamie baddeley on 10/04/2026.
//

import Foundation

/// `URLProtocol` subclass for stubbing `URLSession` responses in tests.
///
/// Set `handler` before each test that uses it. The `ListenerAPITests` suite
/// is `.serialized` so only one test runs at a time, which keeps the static
/// handler safe to mutate.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() {
        handler = nil
    }

    /// Build a `URLSession` whose every request flows through this protocol.
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

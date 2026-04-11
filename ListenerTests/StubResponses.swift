//
//  StubResponses.swift
//  ListenerTests
//
//  Created by jamie baddeley on 11/04/2026.
//

import Foundation

/// Shared free namespace for constructing canned `(Data, HTTPURLResponse)`
/// tuples in tests that use `StubHTTPClient`.
///
/// Lives at file scope deliberately, not as helper methods on a test struct:
/// `StubHTTPClient` invokes its handler from the `ListenerAPI` actor's
/// executor (not the main actor), so any `@MainActor`-isolated instance
/// helper would be unreachable from inside the `@Sendable` handler closure.
/// A free `enum` namespace has no isolation, so it's callable from anywhere.
enum StubResponses {

    static let url = URL(string: "https://test.example/api/v1/listener")!

    static func ok(_ json: String) -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(json.utf8), response)
    }

    static func http(
        _ status: Int,
        body: String = "",
        headers: [String: String] = [:]
    ) -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        return (Data(body.utf8), response)
    }
}

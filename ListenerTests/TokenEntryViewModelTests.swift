//
//  TokenEntryViewModelTests.swift
//  ListenerTests
//
//  Created by jamie baddeley on 11/04/2026.
//

import Testing
import Foundation
@testable import Listener

/// `@MainActor` because the system under test (`TokenEntryViewModel`) is
/// `@MainActor`. Stub-response constructors live in a file-private free
/// namespace below so they don't inherit `@MainActor` isolation —
/// `StubHTTPClient` invokes its handler from the `ListenerAPI` actor's
/// executor, which is not the main actor, so any `@MainActor`-isolated
/// helper would fail to compile when called from there.
@Suite("TokenEntryViewModel")
@MainActor
struct TokenEntryViewModelTests {

    private let baseURL = StubResponses.url

    // MARK: - Helpers

    private func makeViewModel(
        handler: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)
    ) -> TokenEntryViewModel {
        TokenEntryViewModel(
            client: StubHTTPClient(handler: handler),
            baseURL: baseURL
        )
    }

    /// Builds a view model whose `HTTPClient` will record an issue if any
    /// network request is made. Used for tests that exercise input
    /// validation paths that should short-circuit before hitting the API.
    private func makeViewModelExpectingNoRequest() -> TokenEntryViewModel {
        makeViewModel(handler: { _ in
            Issue.record("Network request was made when none was expected")
            throw URLError(.unknown)
        })
    }

    // MARK: - Success path

    @Test func successReturnsTrimmedKeyAndClearsErrorState() async throws {
        let viewModel = makeViewModel(handler: { _ in
            StubResponses.ok(Fixtures.authMe)
        })

        let result = await viewModel.verify("  my-listen-key  ")

        #expect(result == "my-listen-key")
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isVerifying == false)
    }

    // MARK: - Input validation

    @Test func emptyInputReturnsNilImmediately() async throws {
        let viewModel = makeViewModelExpectingNoRequest()

        let result = await viewModel.verify("   ")

        #expect(result == nil)
        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - Error paths

    @Test func unauthorizedShowsInvalidKeyMessage() async throws {
        let viewModel = makeViewModel(handler: { _ in
            StubResponses.http(401, body: Fixtures.errorEnvelope)
        })

        let result = await viewModel.verify("bad-key")

        #expect(result == nil)
        #expect(viewModel.errorMessage?.contains("isn't valid") == true)
    }

    @Test func networkFailureShowsConnectivityMessage() async throws {
        let viewModel = makeViewModel(handler: { _ in
            throw URLError(.notConnectedToInternet)
        })

        let result = await viewModel.verify("any-key")

        #expect(result == nil)
        #expect(viewModel.errorMessage?.contains("reach MixMates") == true)
    }

    @Test func rateLimitedShowsTryLaterMessage() async throws {
        let viewModel = makeViewModel(handler: { _ in StubResponses.http(429) })

        let result = await viewModel.verify("any-key")

        #expect(result == nil)
        #expect(viewModel.errorMessage?.contains("Wait a moment") == true)
    }

    @Test func listenDisabledShowsAccountNotEnabledMessage() async throws {
        let viewModel = makeViewModel(handler: { _ in
            StubResponses.ok(Fixtures.authMeListenDisabled)
        })

        let result = await viewModel.verify("valid-but-disabled")

        #expect(result == nil)
        #expect(viewModel.errorMessage?.contains("isn't enabled") == true)
    }

    @Test func unexpectedHTTPErrorFallsBackToGenericMessage() async throws {
        let viewModel = makeViewModel(handler: { _ in StubResponses.http(500) })

        let result = await viewModel.verify("any-key")

        #expect(result == nil)
        #expect(viewModel.errorMessage == "Couldn't verify the key. Try again.")
    }
}

// MARK: - Stub response helpers

/// File-private free namespace for constructing canned `(Data, HTTPURLResponse)`
/// tuples. Lives outside the test struct deliberately: `StubHTTPClient` invokes
/// its handler from the `ListenerAPI` actor's executor (not the main actor),
/// so any helper that lived as a `@MainActor` instance method on the test
/// struct would be unreachable from inside the handler closure. A free `enum`
/// namespace has no isolation, so it's callable from anywhere.
private enum StubResponses {

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

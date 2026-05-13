//
//  AlternateAccountViewModelTests.swift
//  ListenerTests
//
//  Created by jamie baddeley on 13/05/2026.
//

import Testing
import Foundation
@testable import Listener

/// `@MainActor` because the system under test (`AlternateAccountViewModel`)
/// is `@MainActor`. Same `StubResponses` / `StubHTTPClient` plumbing as the
/// other view-model tests — handlers are `@Sendable` and run off the main
/// actor, so helpers stay at file scope rather than instance methods on a
/// `@MainActor`-isolated test struct.
@Suite("AlternateAccountViewModel")
@MainActor
struct AlternateAccountViewModelTests {

    private let baseURL = StubResponses.url

    // MARK: - Helpers

    private func makeViewModel(
        handler: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)
    ) -> AlternateAccountViewModel {
        AlternateAccountViewModel(
            client: StubHTTPClient(handler: handler),
            baseURL: baseURL
        )
    }

    /// Builds a view model whose `HTTPClient` will record an issue if any
    /// network request is made. Used for tests that exercise input
    /// validation paths that should short-circuit before hitting the API.
    private func makeViewModelExpectingNoRequest() -> AlternateAccountViewModel {
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

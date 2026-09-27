//
//  HistoryDetailViewModelTests.swift
//  ListenerTests
//
//  Created by jamie baddeley on 11/04/2026.
//

import Testing
import Foundation
@testable import Listener

/// `@MainActor` because the system under test (`HistoryDetailViewModel`) is
/// `@MainActor`. Stub responses come from the shared `StubResponses`
/// namespace; see `StubResponses.swift` for why it lives at file scope.
///
/// Group loading, selection and sharing used to be tested here. They moved
/// to `TrackShareViewModelTests` along with the code, when the app
/// consolidated on a single sharing surface.
@Suite("HistoryDetailViewModel")
@MainActor
struct HistoryDetailViewModelTests {

    private func makeViewModel(
        handler: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)
    ) -> HistoryDetailViewModel {
        HistoryDetailViewModel(client: StubHTTPClient(handler: handler))
    }

    // MARK: - Load

    @Test func loadPopulatesDetail() async throws {
        let viewModel = makeViewModel(handler: { _ in
            StubResponses.ok(Fixtures.historyDetail)
        })

        await viewModel.load(id: "h_1", token: "t", onUnauthorized: {})

        #expect(viewModel.detail?.id == "h_1")
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func loadFailureSetsErrorAndKeepsDetailNil() async throws {
        let viewModel = makeViewModel(handler: { _ in
            throw URLError(.notConnectedToInternet)
        })

        await viewModel.load(id: "h_1", token: "t", onUnauthorized: {})

        #expect(viewModel.detail == nil)
        #expect(viewModel.errorMessage?.contains("reach MixMates") == true)
    }

    @Test func loadUnauthorizedFiresCallbackAndClearsDetail() async throws {
        let signal = UnauthorizedSignal()
        let viewModel = makeViewModel(handler: { _ in
            StubResponses.http(401, body: Fixtures.errorEnvelope)
        })

        await viewModel.load(
            id: "h_1",
            token: "stale",
            onUnauthorized: { await signal.fire() }
        )

        #expect(await signal.fired)
        #expect(viewModel.detail == nil)
    }

    // MARK: - Quiet refresh

    /// The share sheet can add shares while this screen sits behind it, so
    /// dismissing it refetches. The read-only "Shared to" list must pick the
    /// new ones up.
    @Test func refreshQuietlyPicksUpNewShares() async throws {
        let calls = CallCounter()
        let viewModel = makeViewModel(handler: { _ in
            calls.next() == 1
                ? StubResponses.ok(Fixtures.historyDetailNoShares)
                : StubResponses.ok(Fixtures.historyDetail)
        })

        await viewModel.load(id: "h_1", token: "t", onUnauthorized: {})
        #expect(viewModel.detail?.sharedTo.isEmpty == true)

        await viewModel.refreshQuietly(id: "h_1", token: "t", onUnauthorized: {})

        #expect(viewModel.detail?.sharedTo.isEmpty == false)
    }

    /// A failed quiet refresh must leave the screen exactly as it was. The
    /// visible detail is still valid, and throwing an error alert over
    /// content the reader is already looking at would be worse than a
    /// slightly stale shared-to list.
    @Test func refreshQuietlyFailureKeepsDetailAndStaysSilent() async throws {
        let calls = CallCounter()
        let viewModel = makeViewModel(handler: { _ in
            if calls.next() == 1 {
                return StubResponses.ok(Fixtures.historyDetail)
            }
            throw URLError(.notConnectedToInternet)
        })

        await viewModel.load(id: "h_1", token: "t", onUnauthorized: {})
        #expect(viewModel.detail != nil)

        await viewModel.refreshQuietly(id: "h_1", token: "t", onUnauthorized: {})

        #expect(viewModel.detail != nil)
        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - Error dismissal

    @Test func clearErrorClearsErrorMessage() async {
        let viewModel = makeViewModel(handler: { _ in
            throw URLError(.notConnectedToInternet)
        })
        await viewModel.load(id: "h_1", token: "t", onUnauthorized: {})
        #expect(viewModel.errorMessage != nil)

        viewModel.clearError()

        #expect(viewModel.errorMessage == nil)
    }
}

// MARK: - Test helpers

private actor UnauthorizedSignal {
    private(set) var fired = false
    func fire() { fired = true }
}

/// Reference-type counter so a `@Sendable` stub handler can vary its
/// response by call number. Touched only from the test scope and the stub's
/// executor (the same task tree), so the unchecked sendability is sound.
private final class CallCounter: @unchecked Sendable {
    private var count = 0
    func next() -> Int {
        count += 1
        return count
    }
}

//
//  HistoryViewModelTests.swift
//  ListenerTests
//
//  Created by jamie baddeley on 11/04/2026.
//

import Testing
import Foundation
@testable import Listener

/// `@MainActor` because the system under test (`HistoryViewModel`) is
/// `@MainActor`. Stub responses come from the shared `StubResponses`
/// namespace; see `StubResponses.swift` for why it lives at file scope.
@Suite("HistoryViewModel")
@MainActor
struct HistoryViewModelTests {

    private func makeViewModel(
        handler: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)
    ) -> HistoryViewModel {
        HistoryViewModel(client: StubHTTPClient(handler: handler))
    }

    // MARK: - Initial load

    @Test func loadPopulatesItemsAndPaginationState() async throws {
        let viewModel = makeViewModel(handler: { _ in
            StubResponses.ok(Fixtures.history)
        })

        await viewModel.load(token: "t", onUnauthorized: {})

        #expect(viewModel.items.count == 2)
        #expect(viewModel.items[0].id == "h_1")
        #expect(viewModel.items[1].id == "h_2")
        #expect(viewModel.cursor == "next_cursor_token")
        #expect(viewModel.hasMore == true)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func loadEmptyPageReportsEmptyAndNoCursor() async throws {
        let viewModel = makeViewModel(handler: { _ in
            StubResponses.ok(Fixtures.historyEmpty)
        })

        await viewModel.load(token: "t", onUnauthorized: {})

        #expect(viewModel.items.isEmpty)
        #expect(viewModel.cursor == nil)
        #expect(viewModel.hasMore == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func loadNetworkFailureSetsErrorMessage() async throws {
        let viewModel = makeViewModel(handler: { _ in
            throw URLError(.notConnectedToInternet)
        })

        await viewModel.load(token: "t", onUnauthorized: {})

        #expect(viewModel.items.isEmpty)
        #expect(viewModel.errorMessage?.contains("reach MixMates") == true)
    }

    @Test func loadRateLimitedSetsRateLimitMessage() async throws {
        let viewModel = makeViewModel(handler: { _ in
            StubResponses.http(429)
        })

        await viewModel.load(token: "t", onUnauthorized: {})

        #expect(viewModel.errorMessage?.contains("Too many") == true)
    }

    @Test func loadUnauthorizedFiresCallbackAndResetsState() async throws {
        let signal = UnauthorizedSignal()
        let viewModel = makeViewModel(handler: { _ in
            StubResponses.http(401, body: Fixtures.errorEnvelope)
        })

        await viewModel.load(
            token: "stale",
            onUnauthorized: { await signal.fire() }
        )

        #expect(await signal.fired)
        #expect(viewModel.items.isEmpty)
        #expect(viewModel.cursor == nil)
    }

    // MARK: - Pagination

    @Test func loadMoreAppendsItemsAndUpdatesCursor() async throws {
        let viewModel = makeViewModel(handler: { request in
            let url = request.url!
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let hasCursor = components?.queryItems?.contains { $0.name == "cursor" } ?? false
            return StubResponses.ok(hasCursor ? Fixtures.historyPage2 : Fixtures.history)
        })

        await viewModel.load(token: "t", onUnauthorized: {})
        #expect(viewModel.items.count == 2)
        #expect(viewModel.hasMore == true)

        await viewModel.loadMore(token: "t", onUnauthorized: {})

        #expect(viewModel.items.count == 3)
        #expect(viewModel.items.last?.id == "h_3")
        #expect(viewModel.cursor == nil)
        #expect(viewModel.hasMore == false)
    }

    @Test func loadMoreNoOpsWhenNoCursor() async throws {
        let counter = RequestCounter()
        let viewModel = makeViewModel(handler: { _ in
            counter.increment()
            return StubResponses.ok(Fixtures.historyEmpty)
        })

        await viewModel.load(token: "t", onUnauthorized: {})
        #expect(counter.count == 1)
        #expect(viewModel.cursor == nil)

        await viewModel.loadMore(token: "t", onUnauthorized: {})

        #expect(counter.count == 1) // unchanged — loadMore short-circuited
    }

    @Test func loadMoreFailureKeepsExistingItemsQuietly() async throws {
        let counter = RequestCounter()
        let viewModel = makeViewModel(handler: { request in
            counter.increment()
            let url = request.url!
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let hasCursor = components?.queryItems?.contains { $0.name == "cursor" } ?? false
            if hasCursor {
                throw URLError(.notConnectedToInternet)
            }
            return StubResponses.ok(Fixtures.history)
        })

        await viewModel.load(token: "t", onUnauthorized: {})
        let originalItems = viewModel.items

        await viewModel.loadMore(token: "t", onUnauthorized: {})

        #expect(viewModel.items == originalItems)
        // Pagination failures are deliberately quiet — no error message,
        // no items removed, the existing list stays visible.
        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - Delete

    @Test func deleteRemovesItemFromList() async throws {
        let viewModel = makeViewModel(handler: { request in
            if request.httpMethod == "DELETE" {
                return StubResponses.ok(Fixtures.historyDelete)
            }
            return StubResponses.ok(Fixtures.history)
        })

        await viewModel.load(token: "t", onUnauthorized: {})
        #expect(viewModel.items.count == 2)

        await viewModel.delete(id: "h_1", token: "t", onUnauthorized: {})

        #expect(viewModel.items.count == 1)
        #expect(viewModel.items.first?.id == "h_2")
        #expect(viewModel.errorMessage == nil)
    }

    @Test func deleteFailureRestoresItemAndSetsError() async throws {
        let viewModel = makeViewModel(handler: { request in
            if request.httpMethod == "DELETE" {
                throw URLError(.notConnectedToInternet)
            }
            return StubResponses.ok(Fixtures.history)
        })

        await viewModel.load(token: "t", onUnauthorized: {})
        let originalCount = viewModel.items.count

        await viewModel.delete(id: "h_1", token: "t", onUnauthorized: {})

        #expect(viewModel.items.count == originalCount)
        #expect(viewModel.items.contains { $0.id == "h_1" })
        #expect(viewModel.errorMessage?.contains("Couldn't remove") == true)
    }

    @Test func deleteIgnoresUnknownId() async throws {
        let counter = RequestCounter()
        let viewModel = makeViewModel(handler: { request in
            counter.increment()
            return StubResponses.ok(Fixtures.history)
        })

        await viewModel.load(token: "t", onUnauthorized: {})
        let baseRequestCount = counter.count

        await viewModel.delete(id: "does-not-exist", token: "t", onUnauthorized: {})

        #expect(counter.count == baseRequestCount) // no DELETE request issued
        #expect(viewModel.items.count == 2)
        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - Error dismissal

    @Test func clearErrorClearsErrorMessage() async {
        let viewModel = makeViewModel(handler: { _ in
            throw URLError(.notConnectedToInternet)
        })
        await viewModel.load(token: "t", onUnauthorized: {})
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

/// Reference-type counter so a `@Sendable` stub handler can record how many
/// times it was invoked. The counter is touched only from the test scope
/// and the actor's executor (which is the same task tree), so the unchecked
/// sendability is sound here.
private final class RequestCounter: @unchecked Sendable {
    private(set) var count = 0
    func increment() { count += 1 }
}

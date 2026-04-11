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
@Suite("HistoryDetailViewModel")
@MainActor
struct HistoryDetailViewModelTests {

    private func makeViewModel(
        handler: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)
    ) -> HistoryDetailViewModel {
        HistoryDetailViewModel(client: StubHTTPClient(handler: handler))
    }

    /// Default routing handler. Detail GET returns `Fixtures.historyDetail`,
    /// groups GET returns `Fixtures.groups`, share POST returns
    /// `Fixtures.share`. Tests that want to override one of these pass a
    /// custom handler instead of using this helper.
    private static let defaultHandler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse) = { request in
        let path = request.url?.path ?? ""
        if request.httpMethod == "POST" {
            return StubResponses.ok(Fixtures.share)
        } else if path.hasSuffix("/groups") {
            return StubResponses.ok(Fixtures.groups)
        } else {
            return StubResponses.ok(Fixtures.historyDetail)
        }
    }

    // MARK: - Load

    @Test func loadPopulatesDetailGroupsAndPreselectsSharedGroups() async throws {
        let viewModel = makeViewModel(handler: Self.defaultHandler)

        await viewModel.load(id: "h_1", token: "t", onUnauthorized: {})

        #expect(viewModel.detail?.id == "h_1")
        #expect(viewModel.groups.count == 2)
        #expect(viewModel.groups.map(\.id) == ["g1", "g2"])
        #expect(viewModel.selectedGroupIds == ["g1"])
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func loadDetailFailureSetsErrorAndKeepsDetailNil() async throws {
        let viewModel = makeViewModel(handler: { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/groups") {
                return StubResponses.ok(Fixtures.groups)
            }
            throw URLError(.notConnectedToInternet)
        })

        await viewModel.load(id: "h_1", token: "t", onUnauthorized: {})

        #expect(viewModel.detail == nil)
        #expect(viewModel.errorMessage?.contains("reach MixMates") == true)
    }

    @Test func loadGroupsFailureSetsErrorAndKeepsDetailNil() async throws {
        let viewModel = makeViewModel(handler: { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/groups") {
                throw URLError(.notConnectedToInternet)
            }
            return StubResponses.ok(Fixtures.historyDetail)
        })

        await viewModel.load(id: "h_1", token: "t", onUnauthorized: {})

        // Both must succeed; if either fails the screen falls back to its
        // full-screen error state rather than showing a partial detail.
        #expect(viewModel.detail == nil)
        #expect(viewModel.errorMessage?.contains("reach MixMates") == true)
    }

    @Test func loadUnauthorizedFiresCallbackAndResetsState() async throws {
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
        #expect(viewModel.selectedGroupIds.isEmpty)
    }

    @Test func loadEmptySharedToStartsWithEmptySelection() async throws {
        let viewModel = makeViewModel(handler: { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/groups") {
                return StubResponses.ok(Fixtures.groups)
            }
            return StubResponses.ok(Fixtures.historyDetailNoShares)
        })

        await viewModel.load(id: "h_2", token: "t", onUnauthorized: {})

        #expect(viewModel.detail != nil)
        #expect(viewModel.selectedGroupIds.isEmpty)
    }

    // MARK: - Toggle

    @Test func toggleGroupAddsAndRemoves() async {
        let viewModel = makeViewModel(handler: Self.defaultHandler)
        await viewModel.load(id: "h_1", token: "t", onUnauthorized: {})

        // g1 is preselected from `shared_to`.
        #expect(viewModel.selectedGroupIds == ["g1"])

        viewModel.toggleGroup("g2")
        #expect(viewModel.selectedGroupIds == ["g1", "g2"])

        viewModel.toggleGroup("g1")
        #expect(viewModel.selectedGroupIds == ["g2"])
    }

    @Test func toggleClearsStaleShareResults() async {
        let viewModel = makeViewModel(handler: Self.defaultHandler)
        await viewModel.load(id: "h_1", token: "t", onUnauthorized: {})
        await viewModel.share(token: "t", onUnauthorized: {})
        #expect(viewModel.shareResults != nil)

        viewModel.toggleGroup("g2")

        #expect(viewModel.shareResults == nil)
    }

    // MARK: - Share

    @Test func shareSucceedsAndStoresResults() async throws {
        let viewModel = makeViewModel(handler: Self.defaultHandler)
        await viewModel.load(id: "h_1", token: "t", onUnauthorized: {})

        await viewModel.share(token: "t", onUnauthorized: {})

        let results = try #require(viewModel.shareResults)
        #expect(results.count == 2)
        #expect(results.contains { $0.groupId == "g1" && $0.status == .shared })
        #expect(results.contains { $0.groupId == "g2" && $0.status == .duplicate })
        #expect(viewModel.isSharing == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func shareNoOpsWhenSelectionEmpty() async throws {
        let counter = RequestCounter()
        let viewModel = makeViewModel(handler: { request in
            counter.increment()
            let path = request.url?.path ?? ""
            if request.httpMethod == "POST" {
                return StubResponses.ok(Fixtures.share)
            } else if path.hasSuffix("/groups") {
                return StubResponses.ok(Fixtures.groups)
            } else {
                return StubResponses.ok(Fixtures.historyDetailNoShares)
            }
        })

        await viewModel.load(id: "h_2", token: "t", onUnauthorized: {})
        let countAfterLoad = counter.count
        #expect(viewModel.selectedGroupIds.isEmpty)

        await viewModel.share(token: "t", onUnauthorized: {})

        #expect(counter.count == countAfterLoad) // no POST issued
        #expect(viewModel.shareResults == nil)
    }

    @Test func shareFailureSetsError() async throws {
        let viewModel = makeViewModel(handler: { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "POST" {
                throw URLError(.notConnectedToInternet)
            } else if path.hasSuffix("/groups") {
                return StubResponses.ok(Fixtures.groups)
            } else {
                return StubResponses.ok(Fixtures.historyDetail)
            }
        })

        await viewModel.load(id: "h_1", token: "t", onUnauthorized: {})

        await viewModel.share(token: "t", onUnauthorized: {})

        #expect(viewModel.errorMessage?.contains("Couldn't share") == true)
        #expect(viewModel.isSharing == false)
        #expect(viewModel.shareResults == nil)
    }

    @Test func shareUnauthorizedFiresCallback() async throws {
        let signal = UnauthorizedSignal()
        let viewModel = makeViewModel(handler: { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "POST" {
                return StubResponses.http(401, body: Fixtures.errorEnvelope)
            } else if path.hasSuffix("/groups") {
                return StubResponses.ok(Fixtures.groups)
            } else {
                return StubResponses.ok(Fixtures.historyDetail)
            }
        })

        await viewModel.load(id: "h_1", token: "t", onUnauthorized: {})

        await viewModel.share(
            token: "t",
            onUnauthorized: { await signal.fire() }
        )

        #expect(await signal.fired)
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

/// Reference-type counter so a `@Sendable` stub handler can record how many
/// times it was invoked. The counter is touched only from the test scope
/// and the actor's executor (which is the same task tree), so the unchecked
/// sendability is sound here.
private final class RequestCounter: @unchecked Sendable {
    private(set) var count = 0
    func increment() { count += 1 }
}

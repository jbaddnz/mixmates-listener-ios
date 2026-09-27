//
//  TrackShareViewModelTests.swift
//  ListenerTests
//

import Testing
import Foundation
@testable import Listener

/// `@MainActor` because the system under test is `@MainActor` and has
/// synchronous methods (`toggleGroup`, `resetShareResults`) that read better
/// called directly than hopped to.
///
/// Most of this suite arrived from `HistoryDetailViewModelTests` when
/// sharing moved out of that screen into `TrackShareSheet`.
@Suite("TrackShareViewModel")
@MainActor
struct TrackShareViewModelTests {

    private func makeViewModel(
        handler: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)
    ) -> TrackShareViewModel {
        TrackShareViewModel(client: StubHTTPClient(handler: handler))
    }

    /// Groups on GET, share outcome on POST.
    private static let defaultHandler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse) = { request in
        if request.httpMethod == "POST" {
            return StubResponses.ok(Fixtures.share)
        }
        return StubResponses.ok(Fixtures.groups)
    }

    // MARK: - Load

    @Test func loadPopulatesGroups() async throws {
        let viewModel = makeViewModel(handler: Self.defaultHandler)

        await viewModel.load(preselecting: [], token: "t", onUnauthorized: {})

        let groups = try #require(loadedGroups(viewModel.groupsState))
        #expect(groups.map(\.id) == ["g1", "g2"])
        #expect(viewModel.selectedGroupIds.isEmpty)
    }

    @Test func loadPreselectsGroupsTheTrackIsAlreadyIn() async throws {
        let viewModel = makeViewModel(handler: Self.defaultHandler)

        await viewModel.load(preselecting: ["g1"], token: "t", onUnauthorized: {})

        #expect(viewModel.selectedGroupIds == ["g1"])
    }

    /// The regression this sheet was partly built to fix.
    ///
    /// A group the track was shared into but which the server no longer
    /// returns must not stay selected. Left in, it ticks nothing on screen
    /// yet enables the Share button, posts a stale id, and renders a raw
    /// identifier back at the user because there is no name to resolve.
    @Test func loadIgnoresPreselectedGroupsThatAreNoLongerAvailable() async throws {
        let viewModel = makeViewModel(handler: Self.defaultHandler)

        await viewModel.load(
            preselecting: ["g1", "g_departed"],
            token: "t",
            onUnauthorized: {}
        )

        #expect(viewModel.selectedGroupIds == ["g1"])
    }

    /// Empty is a real, renderable answer and must not read as a failure.
    /// The sheet shows its "No groups yet" slot for this state, which the
    /// planned group-creation flow replaces with a create affordance.
    @Test func loadWithNoGroupsIsLoadedRatherThanFailed() async throws {
        let viewModel = makeViewModel(handler: { _ in
            StubResponses.ok(#"{ "data": { "items": [] } }"#)
        })

        await viewModel.load(preselecting: [], token: "t", onUnauthorized: {})

        let groups = try #require(loadedGroups(viewModel.groupsState))
        #expect(groups.isEmpty)
    }

    /// And a failure must not read as empty. Telling someone with ten groups
    /// that they have none is the worse of the two wrong answers.
    @Test func loadFailureIsFailedRatherThanEmpty() async throws {
        let viewModel = makeViewModel(handler: { _ in
            throw URLError(.notConnectedToInternet)
        })

        await viewModel.load(preselecting: [], token: "t", onUnauthorized: {})

        #expect(viewModel.groupsState == .failed)
        #expect(loadedGroups(viewModel.groupsState) == nil)
    }

    @Test func loadUnauthorizedFiresCallback() async throws {
        let signal = UnauthorizedSignal()
        let viewModel = makeViewModel(handler: { _ in
            StubResponses.http(401, body: Fixtures.errorEnvelope)
        })

        await viewModel.load(
            preselecting: [],
            token: "stale",
            onUnauthorized: { await signal.fire() }
        )

        #expect(await signal.fired)
        #expect(viewModel.groupsState == .failed)
    }

    // MARK: - Selection

    @Test func toggleGroupAddsAndRemoves() async {
        let viewModel = makeViewModel(handler: Self.defaultHandler)
        await viewModel.load(preselecting: ["g1"], token: "t", onUnauthorized: {})

        viewModel.toggleGroup("g2")
        #expect(viewModel.selectedGroupIds == ["g1", "g2"])

        viewModel.toggleGroup("g1")
        #expect(viewModel.selectedGroupIds == ["g2"])
    }

    // MARK: - Share

    @Test func shareSucceedsAndStoresResults() async throws {
        let viewModel = makeViewModel(handler: Self.defaultHandler)
        await viewModel.load(preselecting: ["g1"], token: "t", onUnauthorized: {})

        await viewModel.share(historyId: "h_1", token: "t", onUnauthorized: {})

        let results = try #require(viewModel.shareResults)
        #expect(results.count == 2)
        #expect(results.contains { $0.groupId == "g1" && $0.status == .shared })
        #expect(results.contains { $0.groupId == "g2" && $0.status == .duplicate })
        #expect(viewModel.isSharing == false)
        #expect(viewModel.shareError == nil)
    }

    @Test func shareNoOpsWhenSelectionEmpty() async throws {
        let calls = CallCounter()
        let viewModel = makeViewModel(handler: { request in
            _ = calls.next()
            if request.httpMethod == "POST" {
                return StubResponses.ok(Fixtures.share)
            }
            return StubResponses.ok(Fixtures.groups)
        })

        await viewModel.load(preselecting: [], token: "t", onUnauthorized: {})
        let afterLoad = calls.count
        #expect(viewModel.selectedGroupIds.isEmpty)

        await viewModel.share(historyId: "h_1", token: "t", onUnauthorized: {})

        #expect(calls.count == afterLoad) // no POST issued
        #expect(viewModel.shareResults == nil)
    }

    @Test func shareFailureSetsShareError() async throws {
        let viewModel = makeViewModel(handler: { request in
            if request.httpMethod == "POST" {
                throw URLError(.notConnectedToInternet)
            }
            return StubResponses.ok(Fixtures.groups)
        })
        await viewModel.load(preselecting: ["g1"], token: "t", onUnauthorized: {})

        await viewModel.share(historyId: "h_1", token: "t", onUnauthorized: {})

        #expect(viewModel.shareError?.contains("Couldn't share") == true)
        #expect(viewModel.isSharing == false)
        #expect(viewModel.shareResults == nil)
    }

    /// A curator has frozen the tracklist. Neutral wording, no suggestion
    /// that anything can be bought or unlocked to get around it.
    @Test func shareGroupLockedShowsItsOwnMessage() async throws {
        let viewModel = makeViewModel(handler: { request in
            if request.httpMethod == "POST" {
                return StubResponses.http(
                    403,
                    body: #"{"error":{"code":"group_locked","message":"Group is in mastering mode"}}"#
                )
            }
            return StubResponses.ok(Fixtures.groups)
        })
        await viewModel.load(preselecting: ["g1"], token: "t", onUnauthorized: {})

        await viewModel.share(historyId: "h_1", token: "t", onUnauthorized: {})

        #expect(viewModel.shareError == "This group is no longer accepting new tracks")
    }

    @Test func shareUnauthorizedFiresCallback() async throws {
        let signal = UnauthorizedSignal()
        let viewModel = makeViewModel(handler: { request in
            if request.httpMethod == "POST" {
                return StubResponses.http(401, body: Fixtures.errorEnvelope)
            }
            return StubResponses.ok(Fixtures.groups)
        })
        await viewModel.load(preselecting: ["g1"], token: "t", onUnauthorized: {})

        await viewModel.share(
            historyId: "h_1",
            token: "t",
            onUnauthorized: { await signal.fire() }
        )

        #expect(await signal.fired)
    }

    @Test func resetShareResultsReturnsToThePicker() async throws {
        let viewModel = makeViewModel(handler: Self.defaultHandler)
        await viewModel.load(preselecting: ["g1"], token: "t", onUnauthorized: {})
        await viewModel.share(historyId: "h_1", token: "t", onUnauthorized: {})
        #expect(viewModel.shareResults != nil)

        viewModel.resetShareResults()

        #expect(viewModel.shareResults == nil)
    }
}

// MARK: - Test helpers

/// Free function rather than a method on the suite: the suite is
/// `@MainActor`, and a helper declared on it inherits that isolation, which
/// makes it unusable from the `@Sendable` stub handlers.
private func loadedGroups(_ state: TrackShareViewModel.GroupsState) -> [HumanGroup]? {
    if case .loaded(let groups) = state { return groups }
    return nil
}

private actor UnauthorizedSignal {
    private(set) var fired = false
    func fire() { fired = true }
}

private final class CallCounter: @unchecked Sendable {
    private(set) var count = 0
    func next() -> Int {
        count += 1
        return count
    }
}

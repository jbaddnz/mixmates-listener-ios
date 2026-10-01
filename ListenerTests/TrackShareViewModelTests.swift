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
    /// The sheet shows "No groups yet", or Start a group when the server
    /// allows it.
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

        #expect(viewModel.groupsState == .failed(message: ShareFlowCopy.couldNotLoadGroups, retryable: true))
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
        #expect(viewModel.groupsState == .failed(message: ShareFlowCopy.couldNotLoadGroups, retryable: true))
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

    // MARK: - Refusals that a retry cannot fix

    /// A disabled account fails the same way every time, so the failed
    /// state must not carry a Try again that can never work.
    @Test func loadListenDisabledIsNotRetryable() async throws {
        let viewModel = makeViewModel(handler: { _ in
            StubResponses.http(403, body: Self.errorBody("auth_listen_disabled"))
        })

        await viewModel.load(preselecting: [], token: "t", onUnauthorized: {})

        #expect(viewModel.groupsState == .failed(message: ShareFlowCopy.listenDisabled, retryable: false))
    }

    @Test func shareListenDisabledShowsItsOwnMessage() async throws {
        let viewModel = makeViewModel(handler: { request in
            if request.httpMethod == "POST" {
                return StubResponses.http(403, body: Self.errorBody("auth_listen_disabled"))
            }
            return StubResponses.ok(Fixtures.groups)
        })
        await viewModel.load(preselecting: ["g1"], token: "t", onUnauthorized: {})

        await viewModel.share(historyId: "h_1", token: "t", onUnauthorized: {})

        #expect(viewModel.shareError == ShareFlowCopy.listenDisabled)
    }

    /// Someone who has left a group gets told so, and the group drops out of
    /// the picker and the selection on the reload, so Share cannot post it
    /// again.
    @Test func shareNotGroupMemberSaysSoAndDropsTheGroup() async throws {
        let groupsLoads = CallCounter()
        let viewModel = makeViewModel(handler: { request in
            if request.httpMethod == "POST" {
                return StubResponses.http(403, body: Self.errorBody("not_found"))
            }
            // The second load no longer lists g2.
            return groupsLoads.next() == 1
                ? StubResponses.ok(Fixtures.groups)
                : StubResponses.ok(#"{ "data": { "items": [ { "id": "g1", "name": "Wellington Batucada", "description": null } ] } }"#)
        })
        await viewModel.load(preselecting: ["g1", "g2"], token: "t", onUnauthorized: {})

        await viewModel.share(historyId: "h_1", token: "t", onUnauthorized: {})

        #expect(viewModel.shareError == ShareFlowCopy.notGroupMember)
        #expect(loadedGroups(viewModel.groupsState)?.map(\.id) == ["g1"])
        #expect(viewModel.selectedGroupIds == ["g1"])
    }

    // MARK: - Names

    @Test func shareNameRequiredAsksForANameAndKeepsTheSelection() async throws {
        let viewModel = makeViewModel(handler: { request in
            if request.httpMethod == "POST" {
                return StubResponses.http(403, body: Self.errorBody("name_required"))
            }
            return StubResponses.ok(Fixtures.groups)
        })
        await viewModel.load(preselecting: ["g1"], token: "t", onUnauthorized: {})

        await viewModel.share(historyId: "h_1", token: "t", onUnauthorized: {})

        #expect(viewModel.isAskingForName)
        #expect(viewModel.shareError == nil)
        #expect(viewModel.selectedGroupIds == ["g1"])
    }

    /// The whole point of the prompt: one name, then the refused share goes
    /// through without the person starting again.
    @Test func submitNameSavesItThenRetriesTheShare() async throws {
        let log = RequestLog()
        let shares = CallCounter()
        let viewModel = makeViewModel(handler: { request in
            log.append(request)
            switch request.httpMethod {
            case "PATCH":
                return StubResponses.ok(Fixtures.authMe)
            case "POST":
                return shares.next() == 1
                    ? StubResponses.http(403, body: Self.errorBody("name_required"))
                    : StubResponses.ok(Fixtures.share)
            default:
                return StubResponses.ok(Fixtures.groups)
            }
        })
        await viewModel.load(preselecting: ["g1"], token: "t", onUnauthorized: {})
        await viewModel.share(historyId: "h_1", token: "t", onUnauthorized: {})

        let profile = await viewModel.submitName("  Jamie  ", historyId: "h_1", token: "t", onUnauthorized: {})

        #expect(profile?.displayName == "Jamie")
        #expect(viewModel.isAskingForName == false)
        #expect(viewModel.shareResults != nil)
        #expect(log.methods == ["GET", "POST", "PATCH", "POST"])
        let patchBody = log.requests[2].httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        #expect(patchBody?["display_name"] as? String == "Jamie")
    }

    /// Retried once, not in a loop. If the server still refuses after the
    /// name is saved, something else is wrong and asking again would hide it.
    @Test func submitNameRetriesOnlyOnce() async throws {
        let log = RequestLog()
        let viewModel = makeViewModel(handler: { request in
            log.append(request)
            switch request.httpMethod {
            case "PATCH": return StubResponses.ok(Fixtures.authMe)
            case "POST": return StubResponses.http(403, body: Self.errorBody("name_required"))
            default: return StubResponses.ok(Fixtures.groups)
            }
        })
        await viewModel.load(preselecting: ["g1"], token: "t", onUnauthorized: {})
        await viewModel.share(historyId: "h_1", token: "t", onUnauthorized: {})

        _ = await viewModel.submitName("Jamie", historyId: "h_1", token: "t", onUnauthorized: {})

        #expect(viewModel.isAskingForName == false)
        #expect(viewModel.shareError == ShareFlowCopy.couldNotShare)
        #expect(log.methods.filter { $0 == "POST" }.count == 2)
    }

    @Test func submitNamePrivateRelayShowsItsCopyAndStaysInTheField() async throws {
        let viewModel = makeViewModel(handler: { request in
            switch request.httpMethod {
            case "PATCH": return StubResponses.http(400, body: Self.errorBody("private_relay_name"))
            case "POST": return StubResponses.http(403, body: Self.errorBody("name_required"))
            default: return StubResponses.ok(Fixtures.groups)
            }
        })
        await viewModel.load(preselecting: ["g1"], token: "t", onUnauthorized: {})
        await viewModel.share(historyId: "h_1", token: "t", onUnauthorized: {})

        let profile = await viewModel.submitName("abc@privaterelay.appleid.com", historyId: "h_1", token: "t", onUnauthorized: {})

        #expect(profile == nil)
        #expect(viewModel.isAskingForName)
        #expect(viewModel.nameError == ShareFlowCopy.privateRelayName)
    }

    /// The relay copy is for the relay refusal only. A plain bad value must
    /// not tell someone they typed an Apple address.
    @Test func submitNameInvalidFieldDoesNotShowTheRelayCopy() async throws {
        let viewModel = makeViewModel(handler: { request in
            switch request.httpMethod {
            case "PATCH": return StubResponses.http(400, body: Self.errorBody("invalid_field"))
            case "POST": return StubResponses.http(403, body: Self.errorBody("name_required"))
            default: return StubResponses.ok(Fixtures.groups)
            }
        })
        await viewModel.load(preselecting: ["g1"], token: "t", onUnauthorized: {})
        await viewModel.share(historyId: "h_1", token: "t", onUnauthorized: {})

        _ = await viewModel.submitName("Jamie", historyId: "h_1", token: "t", onUnauthorized: {})

        #expect(viewModel.nameError == ShareFlowCopy.couldNotSaveName)
    }

    @Test func submitNameIgnoresABlankName() async throws {
        let log = RequestLog()
        let viewModel = makeViewModel(handler: { request in
            log.append(request)
            if request.httpMethod == "POST" {
                return StubResponses.http(403, body: Self.errorBody("name_required"))
            }
            return StubResponses.ok(Fixtures.groups)
        })
        await viewModel.load(preselecting: ["g1"], token: "t", onUnauthorized: {})
        await viewModel.share(historyId: "h_1", token: "t", onUnauthorized: {})

        let profile = await viewModel.submitName("   ", historyId: "h_1", token: "t", onUnauthorized: {})

        #expect(profile == nil)
        #expect(log.methods.contains("PATCH") == false)
        #expect(viewModel.isAskingForName)
    }

    @Test func cancelNameEntryReturnsToThePickerWithTheSelection() async throws {
        let viewModel = makeViewModel(handler: { request in
            if request.httpMethod == "POST" {
                return StubResponses.http(403, body: Self.errorBody("name_required"))
            }
            return StubResponses.ok(Fixtures.groups)
        })
        await viewModel.load(preselecting: ["g1"], token: "t", onUnauthorized: {})
        await viewModel.share(historyId: "h_1", token: "t", onUnauthorized: {})

        viewModel.cancelNameEntry()

        #expect(viewModel.isAskingForName == false)
        #expect(viewModel.selectedGroupIds == ["g1"])
    }

    // MARK: - Whether Start a group is offered

    /// The server decides. `canCreate` comes only from a loaded response,
    /// and the list's contents play no part.
    @Test func loadCarriesCanCreateFromTheResponse() async throws {
        let viewModel = makeViewModel(handler: { _ in StubResponses.ok(Fixtures.groupsWithCreate) })

        await viewModel.load(preselecting: [], token: "t", onUnauthorized: {})

        #expect(loadedList(viewModel.groupsState)?.canCreate == true)
    }

    @Test func loadWithCanCreateFalseDoesNotOfferStart() async throws {
        let viewModel = makeViewModel(handler: { _ in
            StubResponses.ok(#"{ "data": { "can_create": false, "items": [] } }"#)
        })

        await viewModel.load(preselecting: [], token: "t", onUnauthorized: {})

        #expect(loadedList(viewModel.groupsState)?.canCreate == false)
    }

    /// Missing means no, even with an empty list.
    @Test func loadWithTheFieldMissingDoesNotOfferStart() async throws {
        let viewModel = makeViewModel(handler: { _ in
            StubResponses.ok(#"{ "data": { "items": [] } }"#)
        })

        await viewModel.load(preselecting: [], token: "t", onUnauthorized: {})

        #expect(loadedList(viewModel.groupsState)?.canCreate == false)
    }

    /// A failed fetch, offline included, has no `canCreate` to read, so
    /// there is nothing that could offer Start a group.
    @Test func loadFailureCarriesNoCanCreate() async throws {
        let viewModel = makeViewModel(handler: { _ in throw URLError(.notConnectedToInternet) })

        await viewModel.load(preselecting: [], token: "t", onUnauthorized: {})

        #expect(loadedList(viewModel.groupsState) == nil)
    }

    /// Start steps back once any group is ticked, and comes back when
    /// everything is unticked.
    @Test func startGroupDimsWhileAnyGroupIsTicked() async throws {
        let viewModel = makeViewModel(handler: { _ in StubResponses.ok(Fixtures.groupsWithCreate) })
        await viewModel.load(preselecting: [], token: "t", onUnauthorized: {})
        #expect(viewModel.isStartGroupEnabled)

        viewModel.toggleGroup("g1")
        #expect(viewModel.isStartGroupEnabled == false)

        viewModel.toggleGroup("g1")
        #expect(viewModel.isStartGroupEnabled)
    }

    /// From History detail the track's existing groups arrive ticked, so
    /// Start begins dimmed. Known and accepted; pinned so a change to it is
    /// deliberate.
    @Test func startGroupBeginsDimmedWhenGroupsArrivePreselected() async throws {
        let viewModel = makeViewModel(handler: { _ in StubResponses.ok(Fixtures.groupsWithCreate) })

        await viewModel.load(preselecting: ["g1"], token: "t", onUnauthorized: {})

        #expect(viewModel.isStartGroupEnabled == false)
    }

    // MARK: - Starting a group

    /// After a create: the success moment with the new group's invite link,
    /// and the group already in the picker and ticked, without a restart.
    @Test func createGroupShowsTheCreatedMomentAndAddsTheGroup() async throws {
        let log = RequestLog()
        let groupLoads = CallCounter()
        let viewModel = makeViewModel(handler: { request in
            log.append(request)
            switch route(request) {
            case "POST groups":
                return StubResponses.http(201, body: Fixtures.createdGroup)
            default:
                return groupLoads.next() == 1
                    ? StubResponses.ok(Fixtures.groupsWithCreate)
                    : StubResponses.ok(#"""
                    { "data": { "can_create": false, "items": [
                      { "id": "g1", "name": "Wellington Batucada", "description": null, "invite_url": null },
                      { "id": "g_new", "name": "Kitchen Disco", "description": null,
                        "invite_url": "https://mixmat.es/invite/NeWgRoUp5678" } ] } }
                    """#)
            }
        })
        await viewModel.load(preselecting: [], token: "t", onUnauthorized: {})
        viewModel.startGroup()

        await viewModel.createGroup("  Kitchen Disco ", token: "t", onUnauthorized: {})

        guard case .groupCreated(let group) = viewModel.panel else {
            Issue.record("Expected the created state, got \(viewModel.panel)")
            return
        }
        #expect(group.id == "g_new")
        #expect(group.inviteURL == URL(string: "https://mixmat.es/invite/NeWgRoUp5678"))
        #expect(loadedGroups(viewModel.groupsState)?.map(\.id).contains("g_new") == true)
        #expect(loadedList(viewModel.groupsState)?.canCreate == false)
        #expect(viewModel.selectedGroupIds == ["g_new"])
        #expect(log.methods == ["GET", "POST", "GET"])
        let body = log.requests[1].httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        #expect(body?["name"] as? String == "Kitchen Disco")

        viewModel.returnToPicker()
        #expect(viewModel.panel == .picker)
        #expect(viewModel.selectedGroupIds == ["g_new"])
    }

    /// The group exists once the create succeeded, so a failed re-read must
    /// not lose it, and the account now owns one so Start goes away.
    @Test func createGroupKeepsTheNewGroupWhenTheReloadFails() async throws {
        let groupLoads = CallCounter()
        let viewModel = makeViewModel(handler: { request in
            switch route(request) {
            case "POST groups":
                return StubResponses.http(201, body: Fixtures.createdGroup)
            default:
                if groupLoads.next() == 1 { return StubResponses.ok(Fixtures.groupsWithCreate) }
                throw URLError(.timedOut)
            }
        })
        await viewModel.load(preselecting: [], token: "t", onUnauthorized: {})

        await viewModel.createGroup("Kitchen Disco", token: "t", onUnauthorized: {})

        #expect(loadedGroups(viewModel.groupsState)?.map(\.id) == ["g1", "g_demo", "g_new"])
        #expect(loadedList(viewModel.groupsState)?.canCreate == false)
        #expect(viewModel.selectedGroupIds == ["g_new"])
    }

    @Test func createGroupNameTakenKeepsThePersonInTheField() async throws {
        let viewModel = makeViewModel(handler: { request in
            if route(request) == "POST groups" {
                return StubResponses.http(409, body: Self.errorBody("name_taken"))
            }
            return StubResponses.ok(Fixtures.groupsWithCreate)
        })
        await viewModel.load(preselecting: [], token: "t", onUnauthorized: {})
        viewModel.startGroup()

        await viewModel.createGroup("Friends", token: "t", onUnauthorized: {})

        #expect(viewModel.panel == .startingGroup)
        #expect(viewModel.createError == "That name's taken. Try adding something of your own to it.")
    }

    /// The list was stale. Say so in the agreed words and re-read it, so
    /// can_create comes back false and Start goes away.
    @Test func createGroupAlreadyHasGroupSaysSoAndRefreshes() async throws {
        let groupLoads = CallCounter()
        let viewModel = makeViewModel(handler: { request in
            if route(request) == "POST groups" {
                return StubResponses.http(403, body: Self.errorBody("already_has_group"))
            }
            return groupLoads.next() == 1
                ? StubResponses.ok(Fixtures.groupsWithCreate)
                : StubResponses.ok(#"{ "data": { "can_create": false, "items": [] } }"#)
        })
        await viewModel.load(preselecting: [], token: "t", onUnauthorized: {})
        viewModel.startGroup()

        await viewModel.createGroup("Second", token: "t", onUnauthorized: {})

        #expect(viewModel.createError == "This account already has a group.")
        #expect(loadedList(viewModel.groupsState)?.canCreate == false)
        #expect(groupLoads.count == 2)
    }

    @Test func createGroupRateLimitedSaysToWait() async throws {
        let viewModel = makeViewModel(handler: { request in
            if route(request) == "POST groups" {
                return StubResponses.http(429, headers: ["Retry-After": "600"])
            }
            return StubResponses.ok(Fixtures.groupsWithCreate)
        })
        await viewModel.load(preselecting: [], token: "t", onUnauthorized: {})

        await viewModel.createGroup("Kitchen Disco", token: "t", onUnauthorized: {})

        #expect(viewModel.createError == ShareFlowCopy.tooManyTries)
    }

    @Test func createGroupIgnoresABlankName() async throws {
        let log = RequestLog()
        let viewModel = makeViewModel(handler: { request in
            log.append(request)
            return StubResponses.ok(Fixtures.groupsWithCreate)
        })
        await viewModel.load(preselecting: [], token: "t", onUnauthorized: {})

        await viewModel.createGroup("   ", token: "t", onUnauthorized: {})

        #expect(log.methods == ["GET"])
    }

    @Test func cancelStartGroupReturnsToThePicker() async throws {
        let viewModel = makeViewModel(handler: { _ in StubResponses.ok(Fixtures.groupsWithCreate) })
        await viewModel.load(preselecting: [], token: "t", onUnauthorized: {})
        viewModel.startGroup()

        viewModel.cancelStartGroup()

        #expect(viewModel.panel == .picker)
    }

    /// A create refused for want of a name asks for one, keeps the typed
    /// group name, and creates the group once the name is saved.
    @Test func createGroupNameRequiredAsksThenCreatesOnce() async throws {
        let log = RequestLog()
        let creates = CallCounter()
        let viewModel = makeViewModel(handler: { request in
            log.append(request)
            switch route(request) {
            case "POST groups":
                return creates.next() == 1
                    ? StubResponses.http(403, body: Self.errorBody("name_required"))
                    : StubResponses.http(201, body: Fixtures.createdGroup)
            case "PATCH me":
                return StubResponses.ok(Fixtures.authMe)
            default:
                return StubResponses.ok(Fixtures.groupsWithCreate)
            }
        })
        await viewModel.load(preselecting: [], token: "t", onUnauthorized: {})
        viewModel.startGroup()

        await viewModel.createGroup("Kitchen Disco", token: "t", onUnauthorized: {})
        #expect(viewModel.panel == .askingForName(then: .createGroup(name: "Kitchen Disco")))

        let profile = await viewModel.submitName("Jamie", historyId: "h_1", token: "t", onUnauthorized: {})

        #expect(profile?.displayName == "Jamie")
        if case .groupCreated = viewModel.panel {} else {
            Issue.record("Expected the created state, got \(viewModel.panel)")
        }
        #expect(log.methods == ["GET", "POST", "PATCH", "POST", "GET"])
    }

    /// Not now on a name asked for by a create goes back to the group-name
    /// field, not the picker.
    @Test func cancelNameEntryFromACreateReturnsToTheField() async throws {
        let viewModel = makeViewModel(handler: { request in
            if route(request) == "POST groups" {
                return StubResponses.http(403, body: Self.errorBody("name_required"))
            }
            return StubResponses.ok(Fixtures.groupsWithCreate)
        })
        await viewModel.load(preselecting: [], token: "t", onUnauthorized: {})
        viewModel.startGroup()
        await viewModel.createGroup("Kitchen Disco", token: "t", onUnauthorized: {})

        viewModel.cancelNameEntry()

        #expect(viewModel.panel == .startingGroup)
    }

    /// Static so the `@Sendable` stub handlers can reach it; an instance
    /// helper would inherit the suite's main-actor isolation.
    private nonisolated static func errorBody(_ code: String) -> String {
        #"{"error":{"code":"\#(code)","message":"m"}}"#
    }
}

// MARK: - Test helpers

/// Free function rather than a method on the suite: the suite is
/// `@MainActor`, and a helper declared on it inherits that isolation, which
/// makes it unusable from the `@Sendable` stub handlers.
private func loadedGroups(_ state: TrackShareViewModel.GroupsState) -> [HumanGroup]? {
    loadedList(state)?.groups
}

private func loadedList(_ state: TrackShareViewModel.GroupsState) -> GroupList? {
    if case .loaded(let list) = state { return list }
    return nil
}

/// "METHOD last-path-component", e.g. "POST groups" or "POST share", so a
/// stub can answer the create and the share differently.
private func route(_ request: URLRequest) -> String {
    "\(request.httpMethod ?? "") \(request.url?.lastPathComponent ?? "")"
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

/// Every request a stub saw, in order. Unchecked-`Sendable` like
/// `CallCounter`: the view model awaits each call before making the next,
/// so the stub handler never runs twice at once.
private final class RequestLog: @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    var methods: [String] { requests.map { $0.httpMethod ?? "" } }
    func append(_ request: URLRequest) { requests.append(request) }
}

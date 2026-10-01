//
//  ShareFlowCopyTests.swift
//  ListenerTests
//

import Testing
import Foundation
@testable import Listener

/// Pins the copy rules for the share flow as a test rather than a review
/// checklist, so a string that breaks them fails the build.
///
/// Scoped to `ShareFlowCopy`. The app carries legitimate mixmat.es links
/// elsewhere, in the legal screens and the wordmark.
@Suite("ShareFlowCopy")
struct ShareFlowCopyTests {

    /// The fixed strings plus the ones built around a group name, filled
    /// with a sample, so the rules cover what is actually shown and sent.
    static let everyString = ShareFlowCopy.all + [
        ShareFlowCopy.inviteMessage(for: "Kitchen Disco"),
        ShareFlowCopy.inviteAccessibilityLabel(for: "Kitchen Disco"),
    ]

    @Test(arguments: Self.everyString)
    func namesNoWebsite(_ string: String) {
        #expect(string.localizedCaseInsensitiveContains("mixmat.es") == false)
    }

    /// Nothing in the flow may read as something the person could pay to
    /// change.
    @Test(arguments: Self.everyString)
    func carriesNoCommerceWords(_ string: String) {
        let words = string.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        for forbidden in ["upgrade", "paid", "plan", "subscription", "pricing", "premium", "unlock"] {
            #expect(words.contains(forbidden) == false, "\"\(string)\" contains \(forbidden)")
        }
        #expect(string.lowercased().contains("free tier") == false)
    }

    @Test(arguments: Self.everyString)
    func usesNoEmOrEnDashes(_ string: String) {
        #expect(string.contains("\u{2014}") == false)
        #expect(string.contains("\u{2013}") == false)
    }

    @Test func listsEveryStringOnce() {
        #expect(Set(ShareFlowCopy.all).count == ShareFlowCopy.all.count)
    }

    /// Each refusal gets its own words, and only the fallback suggests that
    /// trying again might work.
    @Test func shareFailureKeysOnTheError() {
        #expect(ShareFlowCopy.shareFailure(APIError.groupLocked(payload: nil)) == ShareFlowCopy.groupLocked)
        #expect(ShareFlowCopy.shareFailure(APIError.notGroupMember(payload: nil)) == ShareFlowCopy.notGroupMember)
        #expect(ShareFlowCopy.shareFailure(APIError.listenDisabled(payload: nil)) == ShareFlowCopy.listenDisabled)
        #expect(ShareFlowCopy.shareFailure(APIError.network(URLError(.timedOut))) == ShareFlowCopy.couldNotShare)
    }

    @Test func createFailureKeysOnTheError() {
        #expect(ShareFlowCopy.createFailure(APIError.nameTaken(payload: nil)) == ShareFlowCopy.nameTaken)
        #expect(ShareFlowCopy.createFailure(APIError.alreadyHasGroup(payload: nil)) == ShareFlowCopy.alreadyHasGroup)
        #expect(ShareFlowCopy.createFailure(APIError.listenDisabled(payload: nil)) == ShareFlowCopy.listenDisabled)
        #expect(ShareFlowCopy.createFailure(APIError.rateLimited(retryAfter: 60, remaining: 0)) == ShareFlowCopy.tooManyTries)
        #expect(ShareFlowCopy.createFailure(APIError.network(URLError(.timedOut))) == ShareFlowCopy.couldNotStartGroup)
    }

    /// The row invite names the group, because the group may be a friend's.
    @Test func inviteFromARowNamesTheGroup() {
        #expect(ShareFlowCopy.inviteMessage(for: "Kitchen Disco") == "Join Kitchen Disco on MixMates:")
        #expect(ShareFlowCopy.inviteAccessibilityLabel(for: "Kitchen Disco") == "Invite a friend to Kitchen Disco")
    }

    /// A rate limit must not say "Try again", the one thing that will not
    /// work straight away.
    @Test func nameSaveFailureKeysOnTheError() {
        #expect(ShareFlowCopy.nameSaveFailure(APIError.privateRelayName(payload: nil)) == ShareFlowCopy.privateRelayName)
        #expect(ShareFlowCopy.nameSaveFailure(APIError.rateLimited(retryAfter: 60, remaining: 0)) == ShareFlowCopy.tooManyTries)
        #expect(ShareFlowCopy.nameSaveFailure(APIError.http(status: 400, payload: nil)) == ShareFlowCopy.couldNotSaveName)
    }
}

@Suite("UserProfile.validDisplayName")
struct DisplayNameValidationTests {

    @Test func trimsSurroundingWhitespace() {
        #expect(UserProfile.validDisplayName("  Jamie \n") == "Jamie")
    }

    @Test func refusesBlank() {
        #expect(UserProfile.validDisplayName("") == nil)
        #expect(UserProfile.validDisplayName("   ") == nil)
    }

    @Test func acceptsExactlyTheLimitAndRefusesOneMore() {
        let limit = UserProfile.displayNameMaxLength
        #expect(UserProfile.validDisplayName(String(repeating: "a", count: limit)) != nil)
        #expect(UserProfile.validDisplayName(String(repeating: "a", count: limit + 1)) == nil)
    }
}

@Suite("HumanGroup.validName")
struct GroupNameValidationTests {

    @Test func trimsSurroundingWhitespace() {
        #expect(HumanGroup.validName("  Kitchen Disco ") == "Kitchen Disco")
    }

    @Test func refusesBlank() {
        #expect(HumanGroup.validName("   ") == nil)
    }

    @Test func acceptsExactlyTheLimitAndRefusesOneMore() {
        let limit = HumanGroup.nameMaxLength
        #expect(HumanGroup.validName(String(repeating: "a", count: limit)) != nil)
        #expect(HumanGroup.validName(String(repeating: "a", count: limit + 1)) == nil)
    }
}

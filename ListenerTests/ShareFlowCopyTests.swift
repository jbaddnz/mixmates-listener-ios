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

    @Test(arguments: ShareFlowCopy.all)
    func namesNoWebsite(_ string: String) {
        #expect(string.localizedCaseInsensitiveContains("mixmat.es") == false)
    }

    /// Nothing in the flow may read as something the person could pay to
    /// change.
    @Test(arguments: ShareFlowCopy.all)
    func carriesNoCommerceWords(_ string: String) {
        let words = string.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        for forbidden in ["upgrade", "paid", "plan", "subscription", "pricing", "premium", "unlock"] {
            #expect(words.contains(forbidden) == false, "\"\(string)\" contains \(forbidden)")
        }
        #expect(string.lowercased().contains("free tier") == false)
    }

    @Test(arguments: ShareFlowCopy.all)
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

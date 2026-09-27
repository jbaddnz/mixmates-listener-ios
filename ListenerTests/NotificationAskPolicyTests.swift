//
//  NotificationAskPolicyTests.swift
//  ListenerTests
//

import Testing
import Foundation
import UserNotifications
@testable import Listener

/// Non-isolated: the policy is a pure function and the storage helpers take
/// their `UserDefaults` by argument, so nothing here touches shared state.
///
/// Each test that needs storage builds its own suite-named `UserDefaults`
/// rather than reaching for `.standard`. Sibling suites run in parallel, and
/// a shared defaults domain is exactly the kind of global mutable state that
/// races when they do.
@Suite("NotificationAskPolicy")
struct NotificationAskPolicyTests {

    private func isolatedDefaults() -> UserDefaults {
        let name = "NotificationAskPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - When to ask

    @Test func asksWhenUndecidedAtAMomentThatWarrantsIt() {
        #expect(NotificationAskPolicy.shouldAsk(
            status: .notDetermined,
            alreadyAsked: false,
            trigger: .existingAccountSignedIn
        ))

        #expect(NotificationAskPolicy.shouldAsk(
            status: .notDetermined,
            alreadyAsked: false,
            trigger: .firstShareSucceeded
        ))
    }

    @Test func staysQuietWithoutATrigger() {
        #expect(NotificationAskPolicy.shouldAsk(
            status: .notDetermined,
            alreadyAsked: false,
            trigger: nil
        ) == false)
    }

    @Test func asksOnlyOnce() {
        #expect(NotificationAskPolicy.shouldAsk(
            status: .notDetermined,
            alreadyAsked: true,
            trigger: .existingAccountSignedIn
        ) == false)
    }

    @Test func doesNotAskSomeoneWhoAlreadySaidYes() {
        #expect(NotificationAskPolicy.shouldAsk(
            status: .authorized,
            alreadyAsked: false,
            trigger: .existingAccountSignedIn
        ) == false)
    }

    /// The system prompt is one-shot. Once refused, the only route back is
    /// the Settings app, so a card offering to turn notifications on would
    /// be promising something it cannot deliver.
    @Test func doesNotAskSomeoneWhoAlreadySaidNo() {
        #expect(NotificationAskPolicy.shouldAsk(
            status: .denied,
            alreadyAsked: false,
            trigger: .firstShareSucceeded
        ) == false)
    }

    @Test func doesNotAskWhenNotificationsArriveQuietlyAlready() {
        #expect(NotificationAskPolicy.shouldAsk(
            status: .provisional,
            alreadyAsked: false,
            trigger: .firstShareSucceeded
        ) == false)
    }

    // MARK: - Remembering that it happened

    @Test func startsHavingNeverAsked() {
        #expect(NotificationAskPolicy.hasBeenAsked(defaults: isolatedDefaults()) == false)
    }

    @Test func remembersThatItAsked() {
        let defaults = isolatedDefaults()

        NotificationAskPolicy.recordAsked(defaults: defaults)

        #expect(NotificationAskPolicy.hasBeenAsked(defaults: defaults))
    }

    /// The two halves have to agree, or the card either never appears or
    /// appears forever.
    @Test func recordingTheAskSuppressesTheNextOne() {
        let defaults = isolatedDefaults()
        NotificationAskPolicy.recordAsked(defaults: defaults)

        #expect(NotificationAskPolicy.shouldAsk(
            status: .notDetermined,
            alreadyAsked: NotificationAskPolicy.hasBeenAsked(defaults: defaults),
            trigger: .existingAccountSignedIn
        ) == false)
    }
}

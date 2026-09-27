//
//  NotificationAskPolicy.swift
//  Listener
//

import Foundation
import UserNotifications

/// The moment that has earned the right to ask about notifications.
///
/// Both are moments where a notification has just become relevant to this
/// particular person, which is the whole rule: the ask rides relevance,
/// happens once, and can be refused.
enum NotificationAskTrigger: Equatable {

    /// Someone signed in to an account that already existed. They have
    /// groups elsewhere, and a good number of them installed this app
    /// specifically because it is how notifications reach an iPhone.
    case existingAccountSignedIn

    /// A track went into a group for the first time from this app. Until
    /// that happens there is nothing for anyone to notify them about.
    case firstShareSucceeded
}

/// Whether to show the pre-permission card, as a pure function of the three
/// things that decide it.
///
/// Kept separate from `PushManager` so the decision can be tested without a
/// `UNUserNotificationCenter` anywhere near it. That matches how the rest of
/// that file is treated: the singleton-touching methods have no seam and no
/// coverage, and the parts worth testing are the ones that are already free
/// of the singleton.
enum NotificationAskPolicy {

    static let askShownKey = "notificationAskShown"

    /// True only for someone who has never been asked and whose permission
    /// is genuinely undecided, at a moment that warrants asking.
    ///
    /// `.denied` deliberately returns false. The system prompt is one-shot,
    /// so once it has been refused the only route back is the Settings app,
    /// and re-showing a card that cannot lead anywhere would be a lie about
    /// what tapping it does. `.authorized` and `.provisional` need no ask.
    static func shouldAsk(
        status: UNAuthorizationStatus,
        alreadyAsked: Bool,
        trigger: NotificationAskTrigger?
    ) -> Bool {
        guard trigger != nil else { return false }
        guard !alreadyAsked else { return false }
        return status == .notDetermined
    }

    /// Whether the card has already been shown on this install.
    ///
    /// Per install rather than per account, and never cleared. Someone who
    /// has seen the card once has seen it, and a second account on the same
    /// phone has the same person behind it.
    static func hasBeenAsked(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: askShownKey)
    }

    /// Record that the card was shown. Called when it appears, not when a
    /// button is pressed: showing it is what spends the one chance, and
    /// "Not now" must not leave it able to come back.
    static func recordAsked(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: askShownKey)
    }
}

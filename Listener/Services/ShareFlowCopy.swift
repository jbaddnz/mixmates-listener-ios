//
//  ShareFlowCopy.swift
//  Listener
//

import Foundation

/// Every user-facing string in the share-into-a-group flow, in one place.
///
/// Gathered here rather than left as inline literals so a test can
/// enumerate them and pin the copy rules: no website named, nothing that
/// reads as commerce, no em or en dashes. The Android sibling carries the
/// same strings word for word, so a change here is a change there too.
///
/// Compiled into the Share Extension as well as the app, because both share
/// tracks into groups and must say the same thing when it goes wrong.
enum ShareFlowCopy {

    static let couldNotLoadGroups = "Couldn't load your groups"
    static let couldNotShare = "Couldn't share. Try again."
    static let groupLocked = "This group is no longer accepting new tracks"
    static let notGroupMember = "You're no longer in that group"

    /// Neutral on purpose. This is an admin switch, and the wording must not
    /// suggest anything the person could buy or unlock to change it.
    static let listenDisabled = "Listening isn't enabled on this account"

    static let namePrompt = "Choose a name your friends will see."
    static let nameHint = "A nickname is fine."
    static let namePlaceholder = "Your name"
    static let nameSubmit = "Save and share"
    static let nameCancel = "Not now"
    static let privateRelayName = "That's an Apple private address. Choose a name your friends will see."
    static let couldNotSaveName = "Couldn't save your name. Try again."

    /// For a rate limit, where trying again straight away is the one thing
    /// that will not work.
    static let tooManyTries = "Too many tries. Try again later."

    static let all: [String] = [
        couldNotLoadGroups, couldNotShare, groupLocked, notGroupMember, listenDisabled,
        namePrompt, nameHint, namePlaceholder, nameSubmit, nameCancel,
        privateRelayName, couldNotSaveName, tooManyTries,
    ]

    /// The message for a display name the server would not save.
    static func nameSaveFailure(_ error: Error) -> String {
        switch error {
        case APIError.privateRelayName: return privateRelayName
        case APIError.rateLimited: return tooManyTries
        default: return couldNotSaveName
        }
    }

    /// The message for a share that failed for any reason other than a
    /// missing display name, which is resolved in place rather than reported.
    ///
    /// Keyed on the typed error so each refusal gets its own words. Only the
    /// fallback invites a retry, because only there might one succeed.
    static func shareFailure(_ error: Error) -> String {
        switch error {
        case APIError.groupLocked: return groupLocked
        case APIError.notGroupMember: return notGroupMember
        case APIError.listenDisabled: return listenDisabled
        default: return couldNotShare
        }
    }
}

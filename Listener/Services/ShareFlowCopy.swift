//
//  ShareFlowCopy.swift
//  Listener
//

import Foundation

/// Every user-facing string in the share-into-a-group flow, including
/// starting a group and inviting to one, in one place.
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

    /// The display-name submit when the refused action was starting a group,
    /// where "Save and share" would promise something that is not happening.
    static let nameSubmitSave = "Save"

    // MARK: Starting a group

    static let startGroup = "Start a group"
    static let startGroupHint = "Make a group, then send your friends the invite link."
    static let groupNamePlaceholder = "Name your group"
    static let createSubmit = "Create"
    static let createCancel = "Cancel"
    static let groupReady = "Your group is ready"
    static let inviteAFriend = "Invite a friend"
    static let shareTrackToNewGroup = "Share this track to it"
    /// Sent with the new group's link after a create. No trailing colon:
    /// iOS hands the link to the receiving app separately, and Messages puts
    /// its preview card above the text, so a colon would point at nothing.
    /// Android, which appends the link to the text, keeps one.
    static let inviteMessageAfterCreate = "I started a group on MixMates. Join me"
    static let nameTaken = "That name's taken. Try adding something of your own to it."
    static let alreadyHasGroup = "This account already has a group."
    static let couldNotStartGroup = "Couldn't start the group. Try again."

    /// Names the group, so VoiceOver does not read the same label on every
    /// row.
    static func inviteAccessibilityLabel(for groupName: String) -> String {
        "Invite a friend to \(groupName)"
    }

    static let all: [String] = [
        couldNotLoadGroups, couldNotShare, groupLocked, notGroupMember, listenDisabled,
        namePrompt, nameHint, namePlaceholder, nameSubmit, nameCancel,
        privateRelayName, couldNotSaveName, tooManyTries, nameSubmitSave,
        startGroup, startGroupHint, groupNamePlaceholder, createSubmit, createCancel,
        groupReady, inviteAFriend, shareTrackToNewGroup, inviteMessageAfterCreate,
        nameTaken, alreadyHasGroup, couldNotStartGroup,
    ]

    /// The message for a group the server would not create, other than for a
    /// missing display name, which is resolved in place.
    static func createFailure(_ error: Error) -> String {
        switch error {
        case APIError.nameTaken: return nameTaken
        case APIError.alreadyHasGroup: return alreadyHasGroup
        case APIError.listenDisabled: return listenDisabled
        case APIError.rateLimited: return tooManyTries
        default: return couldNotStartGroup
        }
    }

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

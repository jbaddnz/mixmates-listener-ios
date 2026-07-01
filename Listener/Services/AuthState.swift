//
//  AuthState.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import Combine
import Foundation

/// App-wide auth state. Holds the current bearer token (or `nil`) and persists
/// changes to the injected `TokenStorage`. The root view observes this and
/// switches between `SignInScreen` and `ListenScreen` accordingly.
///
/// The token is a bearer token issued by `/auth/apple` after a Sign in with
/// Apple authentication, sent as `Authorization: Bearer …` on every
/// authenticated request.
///
/// `import Combine` is required because Xcode 26's `MemberImportVisibility`
/// upcoming feature no longer implicitly re-exports Combine through SwiftUI.
@MainActor
final class AuthState: ObservableObject {

    @Published private(set) var token: String?

    private let storage: TokenStorage

    init(storage: TokenStorage) {
        self.storage = storage
        self.token = (try? storage.get())
    }

    /// Persist a verified token and transition the app into the signed-in state.
    func setToken(_ token: String) {
        // The keychain write is best-effort. If it fails (extremely rare on a
        // healthy device) the in-memory state still flips so the user can use
        // the app for this session; they will be prompted to sign in again on
        // next launch when the keychain read returns nil.
        try? storage.set(token)
        self.token = token
    }

    /// Clear the stored token and return the app to the sign-in state.
    /// Called explicitly from the Settings screen and automatically by the
    /// `ListenerAPI` `onUnauthorized` callback when the API surfaces a 401.
    func signOut() {
        try? storage.clear()
        self.token = nil
    }
}

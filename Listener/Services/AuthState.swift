//
//  AuthState.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import Combine
import Foundation

/// Which identity provider produced the current (or most recent) session.
/// The raw value is persisted to `UserDefaults`, so don't rename cases
/// without a migration.
enum SignInMethod: String {
    case apple
    case google

    /// Provider name for UI copy ("Last time you signed in with Apple.").
    var displayName: String {
        switch self {
        case .apple: return "Apple"
        case .google: return "Google"
        }
    }
}

/// App-wide auth state. Holds the current bearer token (or `nil`) and persists
/// changes to the injected `TokenStorage`. The root view observes this and
/// switches between `SignInScreen` and `ListenScreen` accordingly.
///
/// The token is a bearer token issued by `/auth/apple` or `/auth/google`,
/// sent as `Authorization: Bearer …` on every authenticated request.
///
/// Alongside the token, the identity provider that minted it is recorded to
/// `UserDefaults` as `lastSignInMethod`. It deliberately survives `signOut()`
/// — its whole purpose is to hint, on the sign-in screen, which method the
/// user should reach for after a sign-out or a 401 expiry. Only account
/// deletion erases it, via `eraseLastSignInMethod()`.
///
/// `import Combine` is required because Xcode 26's `MemberImportVisibility`
/// upcoming feature no longer implicitly re-exports Combine through SwiftUI.
@MainActor
final class AuthState: ObservableObject {

    @Published private(set) var token: String?
    @Published private(set) var lastSignInMethod: SignInMethod?

    private let storage: TokenStorage
    private let defaults: UserDefaults

    private static let lastSignInMethodKey = "lastSignInMethod"

    init(storage: TokenStorage, defaults: UserDefaults = .standard) {
        self.storage = storage
        self.defaults = defaults
        self.token = (try? storage.get())
        self.lastSignInMethod = defaults.string(forKey: Self.lastSignInMethodKey)
            .flatMap(SignInMethod.init(rawValue:))
    }

    /// Persist a verified token and transition the app into the signed-in
    /// state, recording which provider produced it.
    func setToken(_ token: String, method: SignInMethod) {
        // The keychain write is best-effort. If it fails (extremely rare on a
        // healthy device) the in-memory state still flips so the user can use
        // the app for this session; they will be prompted to sign in again on
        // next launch when the keychain read returns nil.
        try? storage.set(token)
        self.token = token
        defaults.set(method.rawValue, forKey: Self.lastSignInMethodKey)
        lastSignInMethod = method
    }

    /// Clear the stored token and return the app to the sign-in state.
    /// Called explicitly from the Settings screen and automatically by the
    /// `ListenerAPI` `onUnauthorized` callback when the API surfaces a 401.
    /// `lastSignInMethod` is intentionally kept — see the type doc.
    func signOut() {
        try? storage.clear()
        self.token = nil
    }

    /// Forget which provider was used last. Only account deletion calls this
    /// — after deletion the hint would point at an account that no longer
    /// exists.
    func eraseLastSignInMethod() {
        defaults.removeObject(forKey: Self.lastSignInMethodKey)
        lastSignInMethod = nil
    }
}

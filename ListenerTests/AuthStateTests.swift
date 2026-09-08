//
//  AuthStateTests.swift
//  ListenerTests
//
//  Created by jamie baddeley on 11/04/2026.
//

import Testing
import Foundation
@testable import Listener

/// `@MainActor` because the system under test (`AuthState`) is `@MainActor`
/// and exposes synchronous methods. Matching isolation lets the tests call
/// those methods directly without `await MainActor.run { … }`.
@Suite("AuthState")
@MainActor
struct AuthStateTests {

    /// Fresh, test-isolated UserDefaults suite. A UUID in the suite name
    /// keeps parallel-running tests from sharing state; wiping the domain at
    /// creation guards against leftovers from a previous crashed run.
    private func makeDefaults() -> UserDefaults {
        let suiteName = "AuthStateTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func initialTokenIsNilWhenStorageEmpty() {
        let storage = InMemoryTokenStorage()
        let state = AuthState(storage: storage, defaults: makeDefaults())
        #expect(state.token == nil)
        #expect(state.lastSignInMethod == nil)
    }

    @Test func initialTokenLoadsFromStorage() {
        let storage = InMemoryTokenStorage(initial: "preloaded-key")
        let state = AuthState(storage: storage, defaults: makeDefaults())
        #expect(state.token == "preloaded-key")
    }

    @Test func setTokenPersistsAndUpdatesState() throws {
        let storage = InMemoryTokenStorage()
        let state = AuthState(storage: storage, defaults: makeDefaults())

        state.setToken("new-key", method: .apple)

        #expect(state.token == "new-key")
        #expect(try storage.get() == "new-key")
    }

    @Test func setTokenReplacesPreviousValue() throws {
        let storage = InMemoryTokenStorage(initial: "old-key")
        let state = AuthState(storage: storage, defaults: makeDefaults())

        state.setToken("new-key", method: .apple)

        #expect(state.token == "new-key")
        #expect(try storage.get() == "new-key")
    }

    @Test func signOutClearsTokenAndStorage() throws {
        let storage = InMemoryTokenStorage(initial: "existing-key")
        let state = AuthState(storage: storage, defaults: makeDefaults())

        state.signOut()

        #expect(state.token == nil)
        #expect(try storage.get() == nil)
    }

    @Test func signOutWhenAlreadySignedOutIsHarmless() throws {
        let storage = InMemoryTokenStorage()
        let state = AuthState(storage: storage, defaults: makeDefaults())

        state.signOut()

        #expect(state.token == nil)
        #expect(try storage.get() == nil)
    }

    // MARK: - Last sign-in method

    @Test func setTokenRecordsMethod() {
        let state = AuthState(storage: InMemoryTokenStorage(), defaults: makeDefaults())

        state.setToken("new-key", method: .google)

        #expect(state.lastSignInMethod == .google)
    }

    @Test func lastMethodSurvivesSignOut() {
        let state = AuthState(storage: InMemoryTokenStorage(), defaults: makeDefaults())

        state.setToken("new-key", method: .apple)
        state.signOut()

        #expect(state.token == nil)
        #expect(state.lastSignInMethod == .apple)
    }

    @Test func lastMethodLoadsFromDefaultsOnInit() {
        let defaults = makeDefaults()
        defaults.set("google", forKey: "lastSignInMethod")

        let state = AuthState(storage: InMemoryTokenStorage(), defaults: defaults)

        #expect(state.lastSignInMethod == .google)
    }

    @Test func unknownStoredMethodReadsAsNil() {
        let defaults = makeDefaults()
        defaults.set("facebook", forKey: "lastSignInMethod")

        let state = AuthState(storage: InMemoryTokenStorage(), defaults: defaults)

        #expect(state.lastSignInMethod == nil)
    }

    @Test func eraseClearsMethodAndDefaults() {
        let defaults = makeDefaults()
        let state = AuthState(storage: InMemoryTokenStorage(), defaults: defaults)
        state.setToken("new-key", method: .apple)

        state.eraseLastSignInMethod()

        #expect(state.lastSignInMethod == nil)
        #expect(defaults.string(forKey: "lastSignInMethod") == nil)
    }

    @Test func newMethodOverwritesPrevious() {
        let state = AuthState(storage: InMemoryTokenStorage(), defaults: makeDefaults())

        state.setToken("key-1", method: .apple)
        state.signOut()
        state.setToken("key-2", method: .google)

        #expect(state.lastSignInMethod == .google)
    }
}

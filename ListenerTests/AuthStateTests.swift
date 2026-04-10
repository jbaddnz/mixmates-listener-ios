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

    @Test func initialTokenIsNilWhenStorageEmpty() {
        let storage = InMemoryTokenStorage()
        let state = AuthState(storage: storage)
        #expect(state.token == nil)
    }

    @Test func initialTokenLoadsFromStorage() {
        let storage = InMemoryTokenStorage(initial: "preloaded-key")
        let state = AuthState(storage: storage)
        #expect(state.token == "preloaded-key")
    }

    @Test func setTokenPersistsAndUpdatesState() throws {
        let storage = InMemoryTokenStorage()
        let state = AuthState(storage: storage)

        state.setToken("new-key")

        #expect(state.token == "new-key")
        #expect(try storage.get() == "new-key")
    }

    @Test func setTokenReplacesPreviousValue() throws {
        let storage = InMemoryTokenStorage(initial: "old-key")
        let state = AuthState(storage: storage)

        state.setToken("new-key")

        #expect(state.token == "new-key")
        #expect(try storage.get() == "new-key")
    }

    @Test func signOutClearsTokenAndStorage() throws {
        let storage = InMemoryTokenStorage(initial: "existing-key")
        let state = AuthState(storage: storage)

        state.signOut()

        #expect(state.token == nil)
        #expect(try storage.get() == nil)
    }

    @Test func signOutWhenAlreadySignedOutIsHarmless() throws {
        let storage = InMemoryTokenStorage()
        let state = AuthState(storage: storage)

        state.signOut()

        #expect(state.token == nil)
        #expect(try storage.get() == nil)
    }
}

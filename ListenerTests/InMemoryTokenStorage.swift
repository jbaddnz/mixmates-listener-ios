//
//  InMemoryTokenStorage.swift
//  ListenerTests
//
//  Created by jamie baddeley on 11/04/2026.
//

import Foundation
@testable import Listener

/// Test double for `TokenStorage`. Holds the token in memory so consumers
/// (e.g. `AuthState`) can be tested without touching the real Keychain.
///
/// `KeychainManager`'s own tests use the real Security framework with an
/// isolated test service name — see `KeychainManagerTests`.
final class InMemoryTokenStorage: TokenStorage, @unchecked Sendable {

    private var storedToken: String?

    init(initial: String? = nil) {
        self.storedToken = initial
    }

    func get() throws -> String? { storedToken }
    func set(_ token: String) throws { storedToken = token }
    func clear() throws { storedToken = nil }
}

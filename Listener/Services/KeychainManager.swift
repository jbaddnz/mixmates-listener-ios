//
//  KeychainManager.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import Foundation
import Security

/// Storage interface for the auth bearer token. Abstracted as a protocol so tests
/// can substitute an in-memory implementation (`InMemoryTokenStorage`)
/// without touching the real Keychain.
///
/// `KeychainManager`'s own tests run against the real Keychain with an
/// isolated test service name — see `KeychainManagerTests`. Tests for
/// `AuthState` and other consumers use `InMemoryTokenStorage` for speed and
/// for hermeticity.
protocol TokenStorage: Sendable {
    func get() throws -> String?
    func set(_ token: String) throws
    func clear() throws 
}

/// `Security` framework wrapper that stores the auth bearer token as a generic
/// password item. The service, account, and access group are injectable so
/// tests can isolate themselves from the production keychain entry.
///
/// When `accessGroup` is set to the App Group identifier
/// (`group.es.mixmat.listener`), the keychain item is accessible to the
/// Share Extension and any other target in the same App Group. Without an
/// access group, items are private to the main app.
final class KeychainManager: TokenStorage, @unchecked Sendable {

    enum KeychainError: Error, Equatable {
        case unexpectedStatus(OSStatus)
        case encodingFailed
    }

    static let defaultService = "es.mixmat.listener.token"
    // Legacy label from the Listen Key era. Preserved so existing installs
    // stay signed in after the switch to SIWA-minted bearer tokens; renaming
    // it would miss the keychain entry and force every user to sign in again.
    static let defaultAccount = "listen_key"
    static let sharedAccessGroup = "27DK5QL8RX.es.mixmat.listener.shared"

    let service: String
    let account: String
    let accessGroup: String?

    init(service: String = KeychainManager.defaultService,
         account: String = KeychainManager.defaultAccount,
         accessGroup: String? = nil) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    func get() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let token = String(data: data, encoding: .utf8) else {
                return nil
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func set(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        // Remove any existing entry before adding the new one. `removeIfPresent`
        // tolerates "not found" so this is safe on the first set as well.
        try removeIfPresent()

        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func clear() throws {
        try removeIfPresent()
    }

    /// Migrate a token from a non-shared keychain entry to this (shared)
    /// instance. Call on app launch to ensure users upgrading from v1.0
    /// (which stored the token without an access group) have their Listen
    /// Key available to the Share Extension.
    ///
    /// No-op if this instance has no access group, if a token already exists
    /// in the shared group, or if no token exists in the old location.
    func migrateFromPrivateKeychain() throws {
        guard accessGroup != nil else { return }
        guard try get() == nil else { return }

        let privateManager = KeychainManager(
            service: service,
            account: account,
            accessGroup: nil
        )
        guard let existing = try privateManager.get() else { return }

        try set(existing)
        try privateManager.clear()
    }

    // MARK: - Private

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private func removeIfPresent() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

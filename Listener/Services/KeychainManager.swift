//
//  KeychainManager.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import Foundation
import Security

/// Storage interface for the listen key. Abstracted as a protocol so tests
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

/// `Security` framework wrapper that stores the listen key as a generic
/// password item. The service and account names are injectable so tests can
/// isolate themselves from the production keychain entry.
final class KeychainManager: TokenStorage, @unchecked Sendable {

    enum KeychainError: Error, Equatable {
        case unexpectedStatus(OSStatus)
        case encodingFailed
    }

    static let defaultService = "es.mixmat.listener.token"
    static let defaultAccount = "listen_key"

    let service: String
    let account: String

    init(service: String = KeychainManager.defaultService,
         account: String = KeychainManager.defaultAccount) {
        self.service = service
        self.account = account
    }

    func get() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
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

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func clear() throws {
        try removeIfPresent()
    }

    private func removeIfPresent() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

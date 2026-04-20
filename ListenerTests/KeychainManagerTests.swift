//
//  KeychainManagerTests.swift
//  ListenerTests
//
//  Created by jamie baddeley on 11/04/2026.
//

import Testing
import Foundation
@testable import Listener

/// Exercises the real Security framework against an isolated test service
/// name so production keychain entries are never touched. Each test starts
/// from a clean slate via `init`.
@Suite("KeychainManager", .serialized)
struct KeychainManagerTests {

    private let manager = KeychainManager(
        service: "es.mixmat.listener.tests",
        account: "listen_key"
    )

    init() throws {
        try manager.clear()
    }

    @Test func roundTripStoresAndRetrievesToken() throws {
        try manager.set("hello-key")
        let retrieved = try manager.get()
        #expect(retrieved == "hello-key")
    }

    @Test func getReturnsNilWhenNothingStored() throws {
        let retrieved = try manager.get()
        #expect(retrieved == nil)
    }

    @Test func clearRemovesStoredToken() throws {
        try manager.set("hello-key")
        try manager.clear()
        let retrieved = try manager.get()
        #expect(retrieved == nil)
    }

    @Test func setOverwritesExistingValue() throws {
        try manager.set("first")
        try manager.set("second")
        let retrieved = try manager.get()
        #expect(retrieved == "second")
    }

    @Test func clearIsIdempotent() throws {
        try manager.clear()
        try manager.clear()
        let retrieved = try manager.get()
        #expect(retrieved == nil)
    }

    @Test func roundTripPreservesUnicodeAndPunctuation() throws {
        let key = "tëst_key-with.special~chars/and emoji 🎵"
        try manager.set(key)
        let retrieved = try manager.get()
        #expect(retrieved == key)
    }
}

// MARK: - Migration logic tests
//
// These test the migration logic using two private keychain managers with
// different service names to simulate "old location" vs "new location."
// The real shared access group (27DK5QL8RX.es.mixmat.listener.shared)
// isn't available on the simulator, so device-level keychain sharing is
// verified manually on hardware.

@Suite("KeychainManager migration", .serialized)
struct KeychainMigrationTests {

    private let oldManager = KeychainManager(
        service: "es.mixmat.listener.migration-old",
        account: "listen_key"
    )

    private let newManager = KeychainManager(
        service: "es.mixmat.listener.migration-new",
        account: "listen_key"
    )

    init() throws {
        try oldManager.clear()
        try newManager.clear()
    }

    @Test func migrateMovesTokenFromOldToNew() throws {
        try oldManager.set("my-key")

        try migrateToken(from: oldManager, to: newManager)

        #expect(try newManager.get() == "my-key")
        #expect(try oldManager.get() == nil)
    }

    @Test func migrateIsNoOpWhenNewAlreadyHasToken() throws {
        try oldManager.set("old-key")
        try newManager.set("existing-key")

        try migrateToken(from: oldManager, to: newManager)

        #expect(try newManager.get() == "existing-key")
        #expect(try oldManager.get() == "old-key")
    }

    @Test func migrateIsNoOpWhenNoOldToken() throws {
        try migrateToken(from: oldManager, to: newManager)

        #expect(try newManager.get() == nil)
    }

    @Test func migrateIsNoOpWithoutAccessGroup() throws {
        try oldManager.set("my-key")

        // migrateFromPrivateKeychain is a no-op when accessGroup is nil
        try oldManager.migrateFromPrivateKeychain()

        #expect(try oldManager.get() == "my-key")
    }

    /// Exercises the same read-old → write-new → clear-old logic as
    /// `migrateFromPrivateKeychain`, without requiring a shared access group.
    private func migrateToken(from old: KeychainManager, to new: KeychainManager) throws {
        guard try new.get() == nil else { return }
        guard let existing = try old.get() else { return }
        try new.set(existing)
        try old.clear()
    }
}

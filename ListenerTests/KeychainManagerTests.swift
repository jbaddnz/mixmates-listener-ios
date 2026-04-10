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

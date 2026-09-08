//
//  RecordingLengthTests.swift
//  ListenerTests
//
//  Created by jamie baddeley on 09/09/2026.
//

import Foundation
import Testing
@testable import Listener

/// Non-isolated suite: `RecordingLength` is a namespace of pure functions
/// over `UserDefaults`, no actor concerns. Each test builds its own
/// UUID-suffixed suite so parallel-running tests never share state.
@Suite("RecordingLength")
struct RecordingLengthTests {

    private func makeDefaults() -> UserDefaults {
        let suiteName = "RecordingLengthTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func missingKeyFallsBackToDefault() {
        #expect(RecordingLength.seconds(from: makeDefaults()) == 10)
    }

    @Test func storedValueInRangeIsReturned() {
        let defaults = makeDefaults()
        defaults.set(7, forKey: RecordingLength.key)
        #expect(RecordingLength.seconds(from: defaults) == 7)
    }

    @Test func valueBelowRangeClampsToMinimum() {
        let defaults = makeDefaults()
        defaults.set(3, forKey: RecordingLength.key)
        #expect(RecordingLength.seconds(from: defaults) == 6)
    }

    @Test func valueAboveRangeClampsToMaximum() {
        let defaults = makeDefaults()
        defaults.set(45, forKey: RecordingLength.key)
        #expect(RecordingLength.seconds(from: defaults) == 12)
    }

    @Test func nonIntegerValueFallsBackToDefault() {
        let defaults = makeDefaults()
        defaults.set("fast", forKey: RecordingLength.key)
        #expect(RecordingLength.seconds(from: defaults) == 10)
    }
}

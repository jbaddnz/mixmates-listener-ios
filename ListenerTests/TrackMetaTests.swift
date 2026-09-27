//
//  TrackMetaTests.swift
//  ListenerTests
//

import Testing
import Foundation
@testable import Listener

/// Non-isolated: `TrackMeta` is a plain value type with no actor concerns.
///
/// The label is a cross-client spec, not a local formatting choice. The web
/// app and the Android sibling render the identical string, so these cases
/// are as much a record of the agreed format as a test of this code.
@Suite("TrackMeta")
struct TrackMetaTests {

    private func meta(
        bpm: Double? = nil,
        key: String? = nil,
        scale: KeyScale? = nil
    ) -> TrackMeta {
        TrackMeta(bpm: bpm, musicalKey: key, keyScale: scale)
    }

    // MARK: - The canonical example

    @Test func minorKeyWithTempoMatchesTheSharedSpec() {
        let subject = meta(bpm: 105, key: "FSharp", scale: .minor)
        #expect(subject.label == "105 BPM · F♯m")
    }

    // MARK: - Key names

    @Test(arguments: [
        ("C", "C"),
        ("CSharp", "C♯"),
        ("D", "D"),
        ("Eb", "E♭"),
        ("E", "E"),
        ("F", "F"),
        ("FSharp", "F♯"),
        ("G", "G"),
        ("Ab", "A♭"),
        ("A", "A"),
        ("Bb", "B♭"),
        ("B", "B")
    ])
    func keyNameMapsToItsDisplayForm(raw: String, expected: String) {
        #expect(meta(key: raw, scale: .major).label == expected)
    }

    /// A key spelling we have not seen is still worth showing.
    @Test func unrecognisedKeyPassesThroughUnchanged() {
        #expect(meta(key: "H", scale: .major).label == "H")
    }

    // MARK: - Scale suffix

    @Test func minorAppendsTheSuffix() {
        #expect(meta(key: "A", scale: .minor).label == "Am")
    }

    @Test func majorDoesNot() {
        #expect(meta(key: "A", scale: .major).label == "A")
    }

    @Test func absentScaleDoesNot() {
        #expect(meta(key: "A", scale: nil).label == "A")
    }

    /// An unknown scale should not guess at a suffix.
    @Test func unknownScaleDoesNot() {
        #expect(meta(key: "A", scale: KeyScale(rawValue: "DORIAN")).label == "A")
    }

    // MARK: - Tempo

    @Test func tempoRoundsToWholeBeats() {
        #expect(meta(bpm: 104.4).label == "104 BPM")
        #expect(meta(bpm: 104.5).label == "105 BPM")
        #expect(meta(bpm: 128).label == "128 BPM")
    }

    /// A zero tempo is a server fault, not a measurement. "0 BPM" reads
    /// worse than showing nothing.
    @Test func zeroTempoIsTreatedAsAbsent() {
        #expect(meta(bpm: 0).label == nil)
        #expect(meta(bpm: 0, key: "A", scale: .major).label == "A")
    }

    // MARK: - Partial and empty

    @Test func tempoAloneRendersWithoutASeparator() {
        #expect(meta(bpm: 120).label == "120 BPM")
    }

    @Test func keyAloneRendersWithoutASeparator() {
        #expect(meta(key: "Bb", scale: .minor).label == "B♭m")
    }

    @Test func nothingAtAllIsNil() {
        #expect(meta().label == nil)
        #expect(TrackMeta.empty.label == nil)
    }

    @Test func blankKeyStringIsTreatedAsAbsent() {
        #expect(meta(key: "").label == nil)
        #expect(meta(key: "   ").label == nil)
        #expect(meta(bpm: 90, key: "").label == "90 BPM")
    }

    // MARK: - Scale decoding

    @Test func scaleDecodesKnownValuesCaseInsensitively() {
        #expect(KeyScale(rawValue: "MAJOR") == .major)
        #expect(KeyScale(rawValue: "MINOR") == .minor)
        #expect(KeyScale(rawValue: "minor") == .minor)
    }

    /// New server values must not break the client, per the project's
    /// standing rule for every enum derived from a server string.
    @Test func scaleKeepsUnknownValues() {
        #expect(KeyScale(rawValue: "LYDIAN") == .other("LYDIAN"))
    }
}

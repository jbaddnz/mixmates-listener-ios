//
//  TrackMeta.swift
//  Listener
//

import Foundation

/// Tempo and key for a track, rendered as a single short label under the
/// artist: `105 BPM · F♯m`.
///
/// One value type rather than three loose optionals threaded through
/// `Track`, `HistoryItem` and `HistoryDetail`, so adding a fourth musical
/// field later touches one place and the formatting has somewhere to live
/// that is not a view.
///
/// All three fields are nullable and frequently absent. The server enriches
/// asynchronously, so a track recognised seconds ago usually has nothing
/// here and fills in by the next history fetch. Popular and repeat tracks
/// come back enriched immediately.
///
/// The label must match the web app and the Android sibling exactly, so the
/// formatting rules below are a shared spec rather than a local choice.
struct TrackMeta: Equatable {

    /// Beats per minute, unrounded as the server sends it.
    let bpm: Double?

    /// The key in the server's raw spelling: `C`, `CSharp`, `Eb`, `FSharp`.
    /// Mapped for display by `keyLabel`; unrecognised values pass through
    /// untouched rather than disappearing.
    let musicalKey: String?

    let keyScale: KeyScale?

    static let empty = TrackMeta(bpm: nil, musicalKey: nil, keyScale: nil)

    init(bpm: Double?, musicalKey: String?, keyScale: KeyScale?) {
        self.bpm = bpm
        self.musicalKey = musicalKey
        self.keyScale = keyScale
    }

    /// Build from the three raw wire fields. Every DTO carrying tempo and
    /// key has the same shape, so they all funnel through here rather than
    /// each repeating the scale mapping.
    init(bpm: Double?, musicalKey: String?, keyScaleRaw: String?) {
        self.init(
            bpm: bpm,
            musicalKey: musicalKey,
            keyScale: keyScaleRaw.map(KeyScale.init(rawValue:))
        )
    }

    /// `105 BPM · F♯m`, or either half alone, or `nil` when there is nothing
    /// to say. Callers render the tag only when this is non-nil, so an
    /// unenriched track shows no tag rather than an empty or zeroed one.
    var label: String? {
        var parts: [String] = []

        // A zero or negative tempo would be a server fault rather than a
        // real measurement, and "0 BPM" reads worse than no tag at all.
        if let bpm, bpm > 0 {
            parts.append("\(Int(bpm.rounded())) BPM")
        }

        if let keyLabel {
            parts.append(keyLabel)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The key with its scale suffix: `F♯m` in a minor key, `F♯` otherwise.
    private var keyLabel: String? {
        guard let musicalKey else { return nil }
        let trimmed = musicalKey.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let name = Self.keyNames[trimmed] ?? trimmed
        return keyScale == .minor ? name + "m" : name
    }

    /// Raw server spelling to display form. A value missing from this table
    /// renders as sent: a key we have not seen is still better information
    /// than no key.
    private static let keyNames: [String: String] = [
        "C": "C",
        "CSharp": "C♯",
        "D": "D",
        "Eb": "E♭",
        "E": "E",
        "F": "F",
        "FSharp": "F♯",
        "G": "G",
        "Ab": "A♭",
        "A": "A",
        "Bb": "B♭",
        "B": "B"
    ]
}

/// Major or minor, with the project's usual escape hatch so a new server
/// value cannot break the client.
enum KeyScale: Equatable {
    case major
    case minor
    case other(String)

    init(rawValue: String) {
        switch rawValue.uppercased() {
        case "MAJOR": self = .major
        case "MINOR": self = .minor
        default: self = .other(rawValue)
        }
    }
}

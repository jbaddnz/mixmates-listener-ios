//
//  RecordingLength.swift
//  Listener
//
//  Created by jamie baddeley on 09/09/2026.
//

import Foundation

/// The user-adjustable recording length (Settings → Recording). Written by
/// `SettingsScreen`'s stepper via `@AppStorage`, read by
/// `ListenScreenViewModel` at the moment each recording starts — so a
/// change in Settings applies to the very next tap of the record button,
/// no relaunch needed.
enum RecordingLength {

    static let key = "recordingDurationSeconds"
    static let range = 6...12
    static let defaultSeconds = 10

    /// Current setting, clamped to `range` so a stale or hand-edited
    /// defaults value can never produce an out-of-range recording.
    static func seconds(from defaults: UserDefaults = .standard) -> Int {
        guard let stored = defaults.object(forKey: key) as? Int else {
            return defaultSeconds
        }
        return min(max(stored, range.lowerBound), range.upperBound)
    }
}

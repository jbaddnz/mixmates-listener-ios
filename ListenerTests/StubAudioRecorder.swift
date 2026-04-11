//
//  StubAudioRecorder.swift
//  ListenerTests
//
//  Created by jamie baddeley on 11/04/2026.
//

import Foundation
@testable import Listener

/// Test stub for `AudioRecording`. Returns the canned audio data for any
/// `record(duration:)` call and reports the configured permission status.
/// The simulator has no microphone, so the real `AVAudioRecorderImpl` can
/// never be unit-tested — view-model tests substitute this stub instead.
struct StubAudioRecorder: AudioRecording {
    let audio: Data
    let permissionStatus: AudioPermissionStatus

    init(
        audio: Data = Data([0xDE, 0xAD, 0xBE, 0xEF]),
        permissionStatus: AudioPermissionStatus = .granted
    ) {
        self.audio = audio
        self.permissionStatus = permissionStatus
    }

    @MainActor
    func currentPermissionStatus() -> AudioPermissionStatus {
        permissionStatus
    }

    @MainActor
    func record(duration: TimeInterval) async throws -> Data {
        if permissionStatus == .denied {
            throw AudioRecordingError.permissionDenied
        }
        return audio
    }
}

/// Test stub that always throws the supplied `AudioRecordingError`.
/// Used by view-model tests to exercise error-handling branches.
struct FailingAudioRecorder: AudioRecording {
    let error: AudioRecordingError
    let permissionStatus: AudioPermissionStatus

    init(
        error: AudioRecordingError,
        permissionStatus: AudioPermissionStatus = .granted
    ) {
        self.error = error
        self.permissionStatus = permissionStatus
    }

    @MainActor
    func currentPermissionStatus() -> AudioPermissionStatus {
        permissionStatus
    }

    @MainActor
    func record(duration: TimeInterval) async throws -> Data {
        throw error
    }
}

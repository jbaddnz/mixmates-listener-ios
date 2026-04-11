//
//  StubAudioRecorder.swift
//  ListenerTests
//
//  Created by jamie baddeley on 11/04/2026.
//

import Foundation
@testable import Listener

/// Test stub for `AudioRecording`. Returns the canned audio data on `stop()`
/// and reports the configured permission status. The simulator has no
/// microphone, so the real `AVAudioRecorderImpl` can never be unit-tested
/// — view-model tests substitute this stub instead.
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
    func start() async throws {
        if permissionStatus == .denied {
            throw AudioRecordingError.permissionDenied
        }
    }

    @MainActor
    func stop() async throws -> Data {
        audio
    }

    @MainActor
    func reset() {}
}

/// Test stub that throws a configurable error from `start()` or `stop()`.
/// Used by view-model tests to exercise error-handling branches.
///
/// `error:` (the legacy parameter from before the recorder was split into
/// start/stop) is treated as `errorOnStart` by default for backwards
/// compatibility with tests written against the previous protocol shape.
/// Tests that need to fail at the `stop()` stage instead pass `errorOnStop:`.
struct FailingAudioRecorder: AudioRecording {
    let permissionStatus: AudioPermissionStatus
    let errorOnStart: AudioRecordingError?
    let errorOnStop: AudioRecordingError?

    init(
        error: AudioRecordingError? = nil,
        errorOnStart: AudioRecordingError? = nil,
        errorOnStop: AudioRecordingError? = nil,
        permissionStatus: AudioPermissionStatus = .granted
    ) {
        // `error:` is the legacy parameter — treat as errorOnStart unless
        // an explicit errorOnStart is provided.
        self.errorOnStart = errorOnStart ?? error
        self.errorOnStop = errorOnStop
        self.permissionStatus = permissionStatus
    }

    @MainActor
    func currentPermissionStatus() -> AudioPermissionStatus {
        permissionStatus
    }

    @MainActor
    func start() async throws {
        if let error = errorOnStart {
            throw error
        }
    }

    @MainActor
    func stop() async throws -> Data {
        if let error = errorOnStop {
            throw error
        }
        return Data()
    }

    @MainActor
    func reset() {}
}

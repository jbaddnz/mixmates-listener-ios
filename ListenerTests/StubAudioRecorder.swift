//
//  StubAudioRecorder.swift
//  ListenerTests
//
//  Created by jamie baddeley on 11/04/2026.
//

import Foundation
@testable import Listener

/// Test stub for `AudioRecording`. Returns the canned audio data for any
/// `record(duration:)` call. The simulator has no microphone, so the real
/// `AVAudioRecorderImpl` can never be unit-tested — view-model tests
/// substitute this stub instead.
struct StubAudioRecorder: AudioRecording {
    let audio: Data

    init(audio: Data = Data([0xDE, 0xAD, 0xBE, 0xEF])) {
        self.audio = audio
    }

    @MainActor
    func record(duration: TimeInterval) async throws -> Data {
        audio
    }
}

/// Test stub that always throws the supplied `AudioRecordingError`.
/// Used by view-model tests to exercise error-handling branches.
struct FailingAudioRecorder: AudioRecording {
    let error: AudioRecordingError

    @MainActor
    func record(duration: TimeInterval) async throws -> Data {
        throw error
    }
}

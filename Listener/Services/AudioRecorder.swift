//
//  AudioRecorder.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import AVFoundation
import Foundation

/// Records a short audio clip for recognition.
///
/// The protocol exists so tests can substitute `StubAudioRecorder` —
/// the iOS Simulator has no microphone, so the real `AVAudioRecorderImpl`
/// can only be exercised on a physical device.
///
/// `record(duration:)` is `@MainActor` because the production implementation
/// (`AVAudioRecorderImpl`) is bound to the main actor — it subclasses
/// `NSObject` to conform to `AVAudioRecorderDelegate` and the delegate
/// callbacks need to mutate main-actor-isolated state. Callers (the
/// `ListenScreenViewModel` and friends) are themselves `@MainActor`, so
/// the constraint is invisible at the call site.
protocol AudioRecording: Sendable {
    /// Read the current microphone permission status without prompting
    /// the user. Synchronous because the underlying Apple property getter
    /// (`AVAudioApplication.recordPermission` or
    /// `AVAudioSession.recordPermission`) is cached and synchronous. The
    /// view model calls this on screen appear so the UI can show the
    /// permission-denied prompt proactively if the user has previously
    /// declined.
    @MainActor
    func currentPermissionStatus() -> AudioPermissionStatus

    /// Capture `duration` seconds of audio and return the encoded bytes.
    /// Throws `AudioRecordingError` for any failure (permission denied,
    /// session configuration, recording, file read).
    @MainActor
    func record(duration: TimeInterval) async throws -> Data
}

/// Microphone permission status, as reported by the underlying audio
/// recorder. A small enum that decouples the view model from
/// `AVFoundation`'s `AVAudioApplication.recordPermission` /
/// `AVAudioSession.RecordPermission` types — the view model only knows
/// about this domain enum, not the platform types.
enum AudioPermissionStatus: Equatable {
    case granted
    case denied
    case undetermined
}

/// Errors thrown by `AudioRecording` implementations. Mapped to user-facing
/// messages by `ListenScreenViewModel`.
enum AudioRecordingError: Error, Equatable {
    case permissionDenied
    case sessionConfigurationFailed
    case recordingFailed
    case fileReadFailed
}

/// Production `AudioRecording` backed by `AVAudioRecorder`.
///
/// Implemented as a `@MainActor final class : NSObject` because
/// `AVAudioRecorderDelegate` inherits from `NSObjectProtocol`, which Swift
/// `actor` types cannot satisfy. The community-convergent pattern (Hacking
/// With Swift, Donny Wals, multiple OSS examples) is exactly this shape.
///
/// Delegate methods are marked `nonisolated` because Apple does not
/// document which queue they fire on; they hop back to the main actor via
/// `Task { @MainActor in ... }` before touching any class state.
///
/// The bridge between the delegate-based AVFoundation API and the `async`
/// surface uses `withCheckedThrowingContinuation`. The continuation is
/// stored on the instance so the delegate callbacks can resume it.
@MainActor
final class AVAudioRecorderImpl: NSObject, AudioRecording {

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var continuation: CheckedContinuation<Data, Error>?

    /// Explicitly `nonisolated` so default-value expressions like
    /// `AVAudioRecorderImpl()` can be evaluated from non-isolated contexts —
    /// notably the `@StateObject` autoclosure inside `ListenScreen`. The
    /// init body only calls `super.init()` and does not touch any
    /// main-actor-isolated state, so it is safe to escape isolation here.
    nonisolated override init() {
        super.init()
    }

    func currentPermissionStatus() -> AudioPermissionStatus {
        if #available(iOS 17, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            case .undetermined: return .undetermined
            @unknown default: return .undetermined
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            case .undetermined: return .undetermined
            @unknown default: return .undetermined
            }
        }
    }

    func record(duration: TimeInterval) async throws -> Data {
        guard await ensureRecordPermission() else {
            throw AudioRecordingError.permissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            throw AudioRecordingError.sessionConfigurationFailed
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        // Recording settings per `ios-listener-app.md`: AAC, 44.1kHz, mono,
        // medium quality. Targets ~150-200KB for an 11-second clip, well
        // under the server's 5MB cap.
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        let avRecorder: AVAudioRecorder
        do {
            avRecorder = try AVAudioRecorder(url: url, settings: settings)
        } catch {
            throw AudioRecordingError.recordingFailed
        }
        avRecorder.delegate = self
        self.recorder = avRecorder
        self.fileURL = url

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            avRecorder.record(forDuration: duration)
        }
    }

    /// Returns `true` if the user has granted (or now grants) microphone
    /// permission. Splits by deployment target: iOS 17+ uses the
    /// `AVAudioApplication` async API, iOS 16 wraps the older
    /// `AVAudioSession` callback API in a continuation.
    private func ensureRecordPermission() async -> Bool {
        if #available(iOS 17, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                return await AVAudioApplication.requestRecordPermission()
            @unknown default:
                return false
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                return await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            @unknown default:
                return false
            }
        }
    }

    private func cleanUp() {
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        recorder = nil
        fileURL = nil
        continuation = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

// MARK: - AVAudioRecorderDelegate

extension AVAudioRecorderImpl: AVAudioRecorderDelegate {

    nonisolated func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder,
        successfully flag: Bool
    ) {
        Task { @MainActor in
            self.handleFinish(success: flag)
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder,
        error: Error?
    ) {
        Task { @MainActor in
            self.continuation?.resume(throwing: AudioRecordingError.recordingFailed)
            self.cleanUp()
        }
    }

    private func handleFinish(success: Bool) {
        defer { cleanUp() }

        guard success else {
            continuation?.resume(throwing: AudioRecordingError.recordingFailed)
            return
        }
        guard let url = fileURL else {
            continuation?.resume(throwing: AudioRecordingError.recordingFailed)
            return
        }
        do {
            let data = try Data(contentsOf: url)
            continuation?.resume(returning: data)
        } catch {
            continuation?.resume(throwing: AudioRecordingError.fileReadFailed)
        }
    }
}

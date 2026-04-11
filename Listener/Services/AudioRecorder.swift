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
/// All methods are `@MainActor` because the production implementation
/// (`AVAudioRecorderImpl`) is bound to the main actor — it subclasses
/// `NSObject` to conform to `AVAudioRecorderDelegate` and the delegate
/// callbacks need to mutate main-actor-isolated state. Callers (the
/// `ListenScreenViewModel` and friends) are themselves `@MainActor`, so
/// the constraint is invisible at the call site.
///
/// **Three-method recording lifecycle**: the recorder is split into
/// `start()`, `stop()`, and `reset()` so the duration timer can live in
/// the view model rather than inside the recorder. This enables the
/// "Stop early" feature — the view model can call `stop()` before the
/// timer fires. The previous single-call `record(duration:)` shape made
/// this impossible because the duration was hard-coded into the
/// `AVAudioRecorder.record(forDuration:)` call and the continuation
/// blocked until completion.
///
/// **`stop()` is `async throws`** because `AVAudioRecorder.stop()` does
/// not guarantee the audio file is fully written and closed when it
/// returns — code must wait for `audioRecorderDidFinishRecording(_:successfully:)`
/// on the delegate before reading the file. The `withCheckedThrowingContinuation`
/// bridge that used to span the entire `record(duration:)` call now lives
/// inside `stop()` instead. Verified against Apple Developer Forums and
/// Hacking with Swift on 2026-04-11.
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

    /// Configure the audio session and start recording. Async because
    /// the permission flow may need to prompt the user. Throws
    /// `AudioRecordingError.permissionDenied` if the user declines, or
    /// other `AudioRecordingError` cases on session/recorder setup failure.
    /// Returns immediately after the recorder begins capturing — the view
    /// model owns the duration timer and calls `stop()` to retrieve the
    /// audio.
    @MainActor
    func start() async throws

    /// Stop recording and return the captured audio bytes. Async because
    /// it must wait for the `AVAudioRecorderDelegate` callback that
    /// signals the file has been fully written and closed. Throws
    /// `AudioRecordingError.recordingFailed` if `stop()` is called without
    /// a prior successful `start()`, or if the delegate reports failure.
    @MainActor
    func stop() async throws -> Data

    /// Tear down recorder state. Called after a successful or failed
    /// recording cycle so the next `start()` begins from a clean state.
    /// Idempotent.
    @MainActor
    func reset()
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

    func start() async throws {
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
        // No `forDuration:` — the view model owns the duration timer and
        // calls `stop()` to end the recording. This is what enables the
        // "Stop early" feature.
        avRecorder.record()
    }

    func stop() async throws -> Data {
        guard let recorder = self.recorder else {
            throw AudioRecordingError.recordingFailed
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            recorder.stop()
            // The `audioRecorderDidFinishRecording` delegate callback fires
            // next, which calls `handleFinish` to read the file and resume
            // the continuation.
        }
    }

    func reset() {
        cleanUp()
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

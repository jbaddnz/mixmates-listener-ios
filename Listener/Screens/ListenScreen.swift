//
//  ListenScreen.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import Combine
import SwiftUI
import UIKit

struct ListenScreen: View {

    @EnvironmentObject private var auth: AuthState
    @StateObject private var viewModel = ListenScreenViewModel()
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if let profile = viewModel.profile {
                Text("Hi, \(profile.displayName)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            switch viewModel.state {
            case .idle:
                idleView
            case .recording:
                recordingView
            case .recognising:
                recognisingView
            case .result(let result):
                resultView(for: result)
            case .error(let message):
                errorView(message: message)
            }

            Spacer()
        }
        .padding()
        .animation(.default, value: viewModel.state)
        .animation(.default, value: viewModel.profile)
        .animation(.default, value: viewModel.permissionStatus)
        .navigationTitle("Listen")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.checkPermission()
            await loadProfile()
        }
        .onChange(of: scenePhase) { newPhase in
            // Re-check permission when the user returns to the app — they
            // may have just gone to Settings to grant or revoke microphone
            // access. Profile is not re-fetched because the rate limit only
            // changes when the user records.
            if newPhase == .active {
                viewModel.checkPermission()
            }
        }
        .toolbar {
            if let rateLimit = viewModel.profile?.rateLimit {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text("\(rateLimit.remaining)/\(rateLimit.limit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(rateLimit.remaining) of \(rateLimit.limit) recognitions remaining")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    HistoryScreen()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("History")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    SettingsScreen()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .safeAreaInset(edge: .bottom) {
            MixMatesLinkFooter()
        }
    }

    // MARK: - State views

    @ViewBuilder
    private var idleView: some View {
        if viewModel.permissionStatus == .denied {
            permissionDeniedView
        } else {
            VStack(spacing: 16) {
                Button {
                    Task { await record() }
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.white)
                        .frame(width: 160, height: 160)
                        .background(Circle().fill(LinearGradient.mixmatesBrand))
                }
                Text("Tap to listen")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Microphone access is needed to identify music")
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button {
                openURL(URL(string: UIApplication.openSettingsURLString)!)
            } label: {
                Text("Open Settings")
            }
            .buttonStyle(.bordered)
        }
    }

    private var recordingView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: viewModel.recordingProgress)
                    .stroke(
                        LinearGradient.mixmatesBrand,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.05), value: viewModel.recordingProgress)
            }
            .frame(width: 120, height: 120)

            Text("Listening…")
                .font(.title3)

            Button {
                viewModel.stopRecording()
            } label: {
                Label("Stop early", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
        }
    }

    private var recognisingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(2.0)
            Text("Identifying…")
                .font(.title3)
        }
    }

    @ViewBuilder
    private func resultView(for result: RecognitionResult) -> some View {
        VStack(spacing: 16) {
            switch result.status {
            case .saved, .duplicate:
                if let track = result.track {
                    TrackCard(track: track, isDuplicate: result.status == .duplicate)
                        .padding(.horizontal)
                }
            case .noMatch:
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                    Text("No match found")
                        .font(.title3.weight(.semibold))
                    Text("Try again with clearer audio")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .noLinks:
                Text("\(result.track?.title ?? "Track") identified but no streaming links available")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            case .other:
                Text("Couldn't identify the song.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let historyId = result.historyId {
                if viewModel.reported {
                    Label("Reported", systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        Task { await reportWrong(historyId: historyId) }
                    } label: {
                        Label("Wrong", systemImage: "hand.thumbsdown")
                    }
                    .buttonStyle(.bordered)
                }
            }

            OpenInMixMatesButton()
                .padding(.horizontal)

            Button("Listen again") {
                viewModel.reset()
            }
            .buttonStyle(.bordered)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Try again") {
                viewModel.reset()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func record() async {
        guard let token = auth.token else { return }
        await viewModel.record(
            token: token,
            onUnauthorized: { @MainActor in auth.signOut() }
        )
    }

    private func reportWrong(historyId: String) async {
        guard let token = auth.token else { return }
        await viewModel.reportWrong(
            historyId: historyId,
            token: token,
            onUnauthorized: { @MainActor in auth.signOut() }
        )
    }

    private func loadProfile() async {
        guard let token = auth.token else { return }
        await viewModel.loadProfile(
            token: token,
            onUnauthorized: { @MainActor in auth.signOut() }
        )
    }
}

// MARK: - View model

/// View model for `ListenScreen`. Owns the recording → recognition state
/// machine and translates errors into user-facing messages.
///
/// `@MainActor` because it drives a SwiftUI view. `ObservableObject` rather
/// than `@Observable` because the deployment target is iOS 16, which
/// predates the Observation framework, and the no-third-party-dependencies
/// rule rules out backports. Migrate when iOS 17 becomes the floor.
@MainActor
final class ListenScreenViewModel: ObservableObject {

    enum State: Equatable {
        case idle
        case recording
        case recognising
        case result(RecognitionResult)
        case error(String)
    }

    @Published private(set) var state: State = .idle

    /// Loaded once on screen appear via `loadProfile()`. Drives the
    /// "Hi, $name" greeting and the rate limit indicator in the toolbar.
    /// Preserved across `reset()` so tapping "Listen again" doesn't
    /// re-fetch.
    @Published private(set) var profile: UserProfile?

    /// Microphone permission status, set proactively by `checkPermission()`
    /// on screen appear (and on scene activation, so going to Settings and
    /// back picks up the change) and reactively when `record()` throws
    /// `.permissionDenied`. Drives the permission-denied UI in `idleView`
    /// so the user sees the "Open Settings" prompt without having to tap
    /// the mic button to discover the denial — matches the Android
    /// sibling's UX.
    @Published private(set) var permissionStatus: AudioPermissionStatus = .undetermined

    /// Progress through the current recording, from `0.0` to `1.0`. Driven
    /// by the timer task spawned inside `record()`. Used by the
    /// `recordingView`'s circular progress ring. Reset to `0.0` at the
    /// start of each recording.
    @Published private(set) var recordingProgress: Double = 0.0

    /// Whether the current recognition result has been reported as wrong.
    @Published private(set) var reported = false

    private let audioRecorder: AudioRecording
    private let client: HTTPClient
    private let recordingDuration: TimeInterval
    private let sleep: @Sendable (Duration) async -> Void
    private var recordingTask: Task<Void, Never>?

    /// `recordingDuration` and `sleep` are injectable so unit tests can run
    /// the timer loop in milliseconds rather than the production 11 seconds.
    /// Tests pass a small duration (e.g. `0.05`) and a short real `sleep`
    /// (e.g. `Task.sleep(for: .milliseconds(10))`) so the loop completes
    /// in ~50ms wall clock. The closure-seam pattern matches the project's
    /// existing `HTTPClient` protocol-seam approach for testable async code
    /// (rather than the heavier `Clock` protocol from SE-0329, which would
    /// require writing a custom `TestClock` since Apple doesn't ship one).
    init(
        audioRecorder: AudioRecording = AVAudioRecorderImpl(),
        client: HTTPClient = URLSession.shared,
        recordingDuration: TimeInterval = 11.0,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.audioRecorder = audioRecorder
        self.client = client
        self.recordingDuration = recordingDuration
        self.sleep = sleep
    }

    /// Fetch the signed-in user's profile from `auth/me` and store it.
    /// Called from a `.task` modifier on the screen, so it runs once when
    /// the screen first appears.
    ///
    /// **Failure handling deviates from the Android sibling.** Android
    /// catches any exception (including 401) and sets a generic error
    /// message. iOS routes 401 through `onUnauthorized` (which signs the
    /// user out and returns to TokenEntry) — a stale token *should*
    /// re-route to the entry screen, not show a dead error. Other failures
    /// are silent: the profile is non-essential (no greeting, no rate
    /// limit indicator), the user can still record, the failure doesn't
    /// surface to the UI.
    func loadProfile(
        token: String,
        onUnauthorized: @Sendable @escaping () async -> Void
    ) async {
        let api = ListenerAPI(
            client: client,
            tokenProvider: { token },
            onUnauthorized: onUnauthorized
        )
        do {
            let profile = try await api.me()
            self.profile = profile
        } catch APIError.unauthorized {
            // The api has already invoked onUnauthorized, which signs the
            // user out. Don't update profile state.
        } catch {
            // Quiet failure — profile is non-essential.
        }
    }

    /// Drive the full record → recognise flow. Caller passes the current
    /// auth token (read from `AuthState`) and an `onUnauthorized` closure
    /// that the underlying `ListenerAPI` invokes if the server returns 401
    /// — typically wired to `AuthState.signOut()`.
    ///
    /// The flow:
    /// 1. Call `audioRecorder.start()` to begin capturing
    /// 2. Spawn an internal `Task` that ticks every 50ms, updating
    ///    `recordingProgress` until elapsed time reaches `recordingDuration`
    ///    (or the task is cancelled by `stopRecording()`)
    /// 3. Call `audioRecorder.stop()` to retrieve the audio
    /// 4. Submit to `ListenerAPI.recognize` and update `state`
    ///
    /// `await`s the spawned task so callers (the view's button action,
    /// tests) see the full flow complete in one call. The task handle is
    /// stored on the view model so `stopRecording()` can cancel it from
    /// outside the call site.
    func record(
        token: String,
        onUnauthorized: @Sendable @escaping () async -> Void
    ) async {
        // Guard against double-tap mid-flight.
        switch state {
        case .recording, .recognising:
            return
        case .idle, .result, .error:
            break
        }

        // Start the recorder. Failures here are setup failures (permission
        // denied, session config) — they short-circuit before the timer
        // loop even begins.
        do {
            try await audioRecorder.start()
        } catch AudioRecordingError.permissionDenied {
            self.permissionStatus = .denied
            self.state = .idle
            return
        } catch {
            state = .error(errorMessage(for: error))
            return
        }

        state = .recording
        recordingProgress = 0.0

        // Spawn the timer loop in its own Task so `stopRecording()` can
        // cancel it from outside. **Only the loop is cancellable** — the
        // recognition step that follows must run in the outer (non-
        // cancelled) `record()` context, otherwise `URLSession.send` sees
        // `Task.isCancelled` from this inner task and immediately throws
        // `URLError.cancelled`. That bug shipped to hardware once because
        // `StubHTTPClient` doesn't honour task cancellation, so the unit
        // tests passed even though Stop early was broken on real devices.
        // See `stopEarlyRecognitionRunsAfterCancellation` for the test
        // that locks this in.
        let loopTask = Task { @MainActor in
            await self.runRecordingLoop()
        }
        self.recordingTask = loopTask
        await loopTask.value
        self.recordingTask = nil

        // We're back in the outer Task here, which is NOT cancelled —
        // even if `loopTask` was cancelled by `stopRecording()`. This is
        // exactly what lets the recognition request go through after
        // Stop early.
        await self.finishRecordingAndRecognise(
            token: token,
            onUnauthorized: onUnauthorized
        )
    }

    /// "Stop early" action — cancel the running timer loop. The loop sees
    /// `Task.isCancelled` on its next iteration and breaks out, after
    /// which `record()` proceeds to `finishRecordingAndRecognise` in its
    /// own (uncancelled) context. The user gets whatever audio has been
    /// captured so far, sent to the API normally.
    func stopRecording() {
        recordingTask?.cancel()
    }

    /// 50ms tick loop. Updates `recordingProgress` until elapsed time
    /// reaches `recordingDuration` or the task is cancelled. The loop
    /// uses `Task.isCancelled` rather than throwing because we want
    /// cancellation to fall through to `finishRecordingAndRecognise`,
    /// not abandon the recording.
    private func runRecordingLoop() async {
        let startTime = Date()
        while !Task.isCancelled {
            await sleep(.milliseconds(50))
            let elapsed = Date().timeIntervalSince(startTime)
            self.recordingProgress = min(elapsed / recordingDuration, 1.0)
            if elapsed >= recordingDuration {
                break
            }
        }
    }

    /// Stop the recorder, retrieve the audio, submit to the API, update
    /// `state` with the result. Always called after `runRecordingLoop`,
    /// regardless of whether the loop exited via timer or cancellation.
    private func finishRecordingAndRecognise(
        token: String,
        onUnauthorized: @Sendable @escaping () async -> Void
    ) async {
        let audio: Data
        do {
            audio = try await audioRecorder.stop()
        } catch {
            state = .error(errorMessage(for: error))
            audioRecorder.reset()
            return
        }

        state = .recognising

        let api = ListenerAPI(
            client: client,
            tokenProvider: { token },
            onUnauthorized: onUnauthorized
        )
        do {
            let result = try await api.recognize(audio: audio, mimeType: "audio/mp4")
            state = .result(result)
        } catch APIError.unauthorized {
            // The api has already invoked onUnauthorized, which signs the
            // user out. The view will re-render to TokenEntry. Reset our
            // local state so when the user signs back in, no stale UI is
            // shown.
            state = .idle
        } catch {
            state = .error(errorMessage(for: error))
        }

        audioRecorder.reset()
    }

    /// Reset the recording state machine to `.idle` while preserving the
    /// loaded `profile` and `permissionStatus`. Tapping "Listen again"
    /// should not re-fetch profile or re-check permission.
    func reset() {
        state = .idle
        reported = false
    }

    func reportWrong(
        historyId: String,
        token: String,
        onUnauthorized: @Sendable @escaping () async -> Void
    ) async {
        let api = ListenerAPI(
            client: client,
            tokenProvider: { token },
            onUnauthorized: onUnauthorized
        )
        do {
            try await api.reportHistory(id: historyId, reason: "wrong_match")
            reported = true
        } catch APIError.http(status: 409, _) {
            reported = true
        } catch {
            // Best-effort — don't surface report failures to the user.
        }
    }

    /// Read the current microphone permission status from the recorder
    /// (synchronous, doesn't trigger a prompt) and store it. Called from
    /// the screen's `.task` modifier on appear, and from the
    /// `scenePhase == .active` change handler so going to Settings and
    /// back picks up any change.
    func checkPermission() {
        permissionStatus = audioRecorder.currentPermissionStatus()
    }

    private func errorMessage(for error: Error) -> String {
        switch error {
        case AudioRecordingError.permissionDenied:
            return "MixMates needs microphone access. Enable it in Settings to listen to songs."
        case AudioRecordingError.sessionConfigurationFailed,
             AudioRecordingError.recordingFailed,
             AudioRecordingError.fileReadFailed:
            return "Couldn't capture audio. Try again."
        case APIError.network:
            return "Couldn't reach MixMates. Check your connection."
        case APIError.rateLimited:
            return "Too many recognitions in a row. Wait a moment and try again."
        case APIError.recognitionUnavailable:
            return "Song recognition is temporarily unavailable. Try again in a minute."
        default:
            return "Couldn't identify the song. Try again."
        }
    }
}

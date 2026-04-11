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
            Text("mixmat.es")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
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
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(2.0)
            Text("Listening…")
                .font(.title3)
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

    private let audioRecorder: AudioRecording
    private let client: HTTPClient

    init(
        audioRecorder: AudioRecording = AVAudioRecorderImpl(),
        client: HTTPClient = URLSession.shared
    ) {
        self.audioRecorder = audioRecorder
        self.client = client
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
    /// listen key (read from `AuthState`) and an `onUnauthorized` closure
    /// that the underlying `ListenerAPI` invokes if the server returns 401
    /// — typically wired to `AuthState.signOut()`.
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

        state = .recording

        let audio: Data
        do {
            audio = try await audioRecorder.record(duration: 11)
        } catch AudioRecordingError.permissionDenied {
            // Update permission state so the view re-renders to the
            // permission-denied prompt instead of an error message.
            // Returning to `.idle` (rather than `.error`) lets the
            // `idleView` switch take over.
            self.permissionStatus = .denied
            self.state = .idle
            return
        } catch {
            state = .error(errorMessage(for: error))
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
    }

    /// Reset the recording state machine to `.idle` while preserving the
    /// loaded `profile` and `permissionStatus`. Tapping "Listen again"
    /// should not re-fetch profile or re-check permission.
    func reset() {
        state = .idle
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

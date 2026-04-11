//
//  ListenScreen.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import Combine
import SwiftUI

struct ListenScreen: View {

    @EnvironmentObject private var auth: AuthState
    @StateObject private var viewModel = ListenScreenViewModel()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

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
        .navigationTitle("Listen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
    }

    // MARK: - State views

    private var idleView: some View {
        VStack(spacing: 16) {
            Button {
                Task { await record() }
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white)
                    .frame(width: 160, height: 160)
                    .background(Circle().fill(.green))
            }
            Text("Tap to listen")
                .font(.callout)
                .foregroundStyle(.secondary)
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
        if let track = result.track {
            VStack(spacing: 16) {
                if let thumbnail = track.thumbnail {
                    AsyncImage(url: thumbnail) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.gray.opacity(0.2))
                    }
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(spacing: 4) {
                    Text(track.title)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(track.artist)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    if let spotify = track.platforms.spotify {
                        Link("Spotify", destination: spotify)
                            .buttonStyle(.bordered)
                    }
                    if let tidal = track.platforms.tidal {
                        Link("Tidal", destination: tidal)
                            .buttonStyle(.bordered)
                    }
                    if let appleMusic = track.platforms.appleMusic {
                        Link("Apple Music", destination: appleMusic)
                            .buttonStyle(.bordered)
                    }
                }

                if let shareURL = track.shareURL {
                    ShareLink(item: shareURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }

                Button("Listen again") {
                    viewModel.reset()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text("No match — try again")
                    .font(.title3)
                Button("Listen again") {
                    viewModel.reset()
                }
                .buttonStyle(.borderedProminent)
            }
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

    private let audioRecorder: AudioRecording
    private let client: HTTPClient

    init(
        audioRecorder: AudioRecording = AVAudioRecorderImpl(),
        client: HTTPClient = URLSession.shared
    ) {
        self.audioRecorder = audioRecorder
        self.client = client
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

    func reset() {
        state = .idle
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

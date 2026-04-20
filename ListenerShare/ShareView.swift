//
//  ShareView.swift
//  ListenerShare
//
//  Created by jamie baddeley on 20/04/2026.
//

import Combine
import SwiftUI

// MARK: - View Model

@MainActor
final class ShareViewModel: ObservableObject {

    enum State: Equatable {
        case loading
        case noAuth
        case noURL
        case resolved(RecognitionResult)
        case error(String)
    }

    @Published private(set) var state: State = .loading

    private let token: String?
    private let dismiss: () -> Void
    private var api: ListenerAPI?

    init(token: String?, dismiss: @escaping () -> Void) {
        self.token = token
        self.dismiss = dismiss

        if let token {
            self.api = ListenerAPI(
                tokenProvider: { token },
                onUnauthorized: {}
            )
        }
    }

    func resolve(url: URL?) async {
        guard let token, token.isEmpty == false else {
            state = .noAuth
            return
        }

        guard let url else {
            state = .noURL
            return
        }

        guard let api else { return }

        do {
            let result = try await api.resolve(url: url)
            state = .resolved(result)
        } catch let error as APIError {
            switch error {
            case .unauthorized:
                state = .noAuth
            case .network:
                state = .error("No internet connection.")
            case .http(_, let payload):
                state = .error(payload?.message ?? "Couldn't resolve this link.")
            default:
                state = .error("Couldn't resolve this link.")
            }
        } catch {
            state = .error("Couldn't resolve this link.")
        }
    }

    func close() {
        dismiss()
    }
}

// MARK: - View

struct ShareView: View {

    @ObservedObject var viewModel: ShareViewModel

    var body: some View {
        NavigationView {
            Group {
                switch viewModel.state {
                case .loading:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Resolving...")
                            .foregroundStyle(.secondary)
                    }

                case .noAuth:
                    unavailableView(
                        "Not signed in",
                        icon: "key",
                        detail: "Open MixMates Listener and enter your Listen Key first."
                    )

                case .noURL:
                    unavailableView(
                        "No music link found",
                        icon: "link",
                        detail: "Share a link from Spotify, Tidal, or Apple Music."
                    )

                case .resolved(let result):
                    resolvedView(result)

                case .error(let message):
                    unavailableView(
                        "Couldn't resolve",
                        icon: "exclamationmark.triangle",
                        detail: message
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("MixMates Listener")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { viewModel.close() }
                }
            }
        }
    }

    @ViewBuilder
    private func resolvedView(_ result: RecognitionResult) -> some View {
        VStack(spacing: 16) {
            if let track = result.track {
                VStack(spacing: 8) {
                    if let thumbnail = track.thumbnail {
                        AsyncImage(url: thumbnail) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.quaternary)
                        }
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Text(track.title)
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    Text(track.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                platformLinks(track.platforms)
                    .padding(.horizontal)

                Label("Saved to your Listen group", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                unavailableView(
                    "No match",
                    icon: "music.note",
                    detail: "Couldn't find this track on other platforms."
                )
            }
        }
        .padding()
    }

    @ViewBuilder
    private func platformLinks(_ platforms: Platforms) -> some View {
        VStack(spacing: 8) {
            if let url = platforms.spotify {
                platformLink("Spotify", url: url, icon: "arrow.up.right")
            }
            if let url = platforms.tidal {
                platformLink("Tidal", url: url, icon: "arrow.up.right")
            }
            if let url = platforms.appleMusic {
                platformLink("Apple Music", url: url, icon: "arrow.up.right")
            }
        }
    }

    private func unavailableView(_ title: String, icon: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func platformLink(_ name: String, url: URL, icon: String) -> some View {
        Link(destination: url) {
            HStack {
                Text(name)
                Spacer()
                Image(systemName: icon)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

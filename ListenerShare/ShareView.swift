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
    @Published private(set) var groups: [HumanGroup] = []
    @Published private(set) var selectedGroupIds: Set<String> = []
    @Published private(set) var isSharing = false
    @Published private(set) var shareResults: [ShareResult]?
    @Published private(set) var shareError: String?

    private let token: String?
    private let dismiss: () -> Void
    private var api: ListenerAPI?
    private var historyId: String?

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
            historyId = result.historyId
            state = .resolved(result)

            // Fetch groups for the share-to-group picker
            do {
                groups = try await api.groups()
            } catch {
                // Non-fatal — the user can still see the result, just
                // can't share to groups.
            }
        } catch let error as APIError {
            switch error {
            case .unauthorized:
                state = .noAuth
            case .network:
                state = .error("No internet connection.")
            case .groupLocked:
                state = .error("This group is no longer accepting new tracks")
            case .http(_, let payload):
                state = .error(payload?.message ?? "Couldn't resolve this link.")
            default:
                state = .error("Couldn't resolve this link.")
            }
        } catch {
            state = .error("Couldn't resolve this link.")
        }
    }

    func toggleGroup(_ id: String) {
        if selectedGroupIds.contains(id) {
            selectedGroupIds.remove(id)
        } else {
            selectedGroupIds.insert(id)
        }
        shareResults = nil
        shareError = nil
    }

    func share() async {
        guard let api, let historyId, !selectedGroupIds.isEmpty else { return }
        isSharing = true
        shareError = nil
        defer { isSharing = false }

        do {
            let outcome = try await api.shareHistory(
                id: historyId,
                groupIds: Array(selectedGroupIds)
            )
            shareResults = outcome.results
        } catch APIError.groupLocked {
            shareError = "This group is no longer accepting new tracks"
        } catch {
            shareError = "Couldn't share. Try again."
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
                        icon: "person.crop.circle.badge.exclamationmark",
                        detail: "Open MixMates Listener and sign in first."
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
        ScrollView {
            VStack(spacing: 16) {
                if let track = result.track {
                    trackCard(track)

                    statusLabel(result.status)

                    platformLinks(track.platforms)
                        .padding(.horizontal)

                    if result.status != .duplicate && !viewModel.groups.isEmpty {
                        Divider()
                            .padding(.horizontal)
                        shareToGroupsSection
                    }
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
    }

    private func trackCard(_ track: Track) -> some View {
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
                .frame(width: 160, height: 160)
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
    }

    @ViewBuilder
    private func statusLabel(_ status: RecognitionStatus) -> some View {
        switch status {
        case .saved:
            Label("Saved to your Listen group", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .duplicate:
            VStack(spacing: 4) {
                Text("Deja vu!")
                    .font(.callout.weight(.bold))
                Text("We've been here before!")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Open the Listener history to see.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Share to groups

    private var shareToGroupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Share to group")
                .font(.headline)

            ForEach(viewModel.groups) { group in
                Button {
                    viewModel.toggleGroup(group.id)
                } label: {
                    let isSelected = viewModel.selectedGroupIds.contains(group.id)
                    HStack(spacing: 12) {
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        Text(group.name)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            Button {
                Task { await viewModel.share() }
            } label: {
                if viewModel.isSharing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Share")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedGroupIds.isEmpty || viewModel.isSharing)

            if let results = viewModel.shareResults {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(results, id: \.groupId) { result in
                        Text(displayStatus(for: result))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let error = viewModel.shareError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
    }

    private func displayStatus(for result: ShareResult) -> String {
        let groupName = viewModel.groups.first(where: { $0.id == result.groupId })?.name ?? result.groupId
        switch result.status {
        case .shared:
            return "Shared to \(groupName)"
        case .duplicate:
            return "Already in \(groupName)"
        case .other(let status):
            return "\(groupName): \(status)"
        }
    }

    // MARK: - Shared components

    private static let spotifyGreen = Color(red: 0x1D / 255, green: 0xB9 / 255, blue: 0x54 / 255)
    private static let tidalCyan = Color(red: 0x00 / 255, green: 0xD4 / 255, blue: 0xFF / 255)
    private static let appleMusicRed = Color(red: 0xFA / 255, green: 0x24 / 255, blue: 0x3C / 255)

    @ViewBuilder
    private func platformLinks(_ platforms: Platforms) -> some View {
        VStack(spacing: 8) {
            if let url = platforms.spotify {
                platformLink("Spotify", url: url, color: Self.spotifyGreen, cornerRadius: 500)
            }
            if let url = platforms.tidal {
                platformLink("Tidal", url: url, color: Self.tidalCyan, cornerRadius: 4)
            }
            if let url = platforms.appleMusic {
                platformLink("Apple Music", url: url, color: Self.appleMusicRed, cornerRadius: 10)
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

    private func platformLink(_ name: String, url: URL, color: Color, cornerRadius: CGFloat) -> some View {
        Link(destination: url) {
            HStack {
                Text(name)
                Spacer()
                Image(systemName: "arrow.up.right")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundStyle(color)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(color, lineWidth: 1)
            )
        }
    }
}

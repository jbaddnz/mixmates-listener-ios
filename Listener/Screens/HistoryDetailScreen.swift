//
//  HistoryDetailScreen.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import Combine
import SwiftUI

/// Detail view for a single saved history item.
///
/// - `TrackCard` at the top (the same component used by `ListenScreen`),
///   whose Share hero opens `TrackShareSheet`
/// - Read-only "Shared to" section listing existing shares
///
/// Sharing itself moved out to `TrackShareSheet`, so this screen and the
/// recognition result now offer one identical surface rather than two
/// implementations of the same picker. This is a deliberate divergence from
/// the Android sibling's `HistoryDetailScreen.kt`, which still carries its
/// picker inline.
struct HistoryDetailScreen: View {

    let id: String

    @EnvironmentObject private var auth: AuthState
    @StateObject private var viewModel = HistoryDetailViewModel()
    @State private var showShareSheet = false

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = viewModel.detail {
                content(for: detail)
            } else if let error = viewModel.errorMessage {
                errorView(message: error)
            }
        }
        .navigationTitle("Track Details")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert(
            "Something went wrong",
            isPresented: errorAlertBinding,
            presenting: viewModel.errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Content

    private func content(for detail: HistoryDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TrackCard(detail: detail, onShare: { showShareSheet = true })

                if !detail.sharedTo.isEmpty {
                    Divider()
                    sharedToSection(groups: detail.sharedTo)
                }
            }
            .padding()
        }
        .sheet(
            isPresented: $showShareSheet,
            onDismiss: { Task { await refreshAfterShare() } }
        ) {
            TrackShareSheet(
                historyId: detail.id,
                shareURL: detail.shareURL,
                alreadySharedTo: detail.sharedTo.map(\.groupId)
            )
            .environmentObject(auth)
        }
    }

    private func sharedToSection(groups: [SharedGroup]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shared to")
                .font(.headline)
            ForEach(groups, id: \.groupId) { group in
                Text(group.groupName)
                    .font(.body)
            }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    /// Pick up any shares made in the sheet, so the read-only "Shared to"
    /// list is not left describing the state of things before it opened.
    private func refreshAfterShare() async {
        guard let token = auth.token else { return }
        await viewModel.refreshQuietly(
            id: id,
            token: token,
            onUnauthorized: { @MainActor in auth.signOut() }
        )
    }

    private func load() async {
        guard let token = auth.token else { return }
        await viewModel.load(
            id: id,
            token: token,
            onUnauthorized: { @MainActor in auth.signOut() }
        )
    }

    /// Two-way binding that surfaces `errorMessage` as an alert ONLY when
    /// the detail loaded successfully (so the user has something to look at
    /// behind the alert). When the initial load fails completely the full
    /// `errorView` takes over the screen instead.
    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil && viewModel.detail != nil },
            set: { isPresented in
                if !isPresented { viewModel.clearError() }
            }
        )
    }
}

// MARK: - View model

/// View model for `HistoryDetailScreen`. Fetches one saved history item.
///
/// Group loading, selection and the share call used to live here as well.
/// They moved to `TrackShareSheet` when the app consolidated on a single
/// sharing surface, which is why this type is now only a detail fetch and
/// why the screen no longer has all-or-nothing load semantics across two
/// endpoints.
///
/// `import Combine` is required because Xcode 26's `MemberImportVisibility`
/// upcoming feature no longer implicitly re-exports Combine through SwiftUI.
@MainActor
final class HistoryDetailViewModel: ObservableObject {

    @Published private(set) var detail: HistoryDetail?
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var errorMessage: String?

    private let client: HTTPClient

    init(client: HTTPClient = URLSession.shared) {
        self.client = client
    }

    /// Fetch the detail, showing the full-screen loading state while it runs
    /// and the full-screen error state if it fails.
    func load(
        id: String,
        token: String,
        onUnauthorized: @Sendable @escaping () async -> Void
    ) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        await fetch(id: id, token: token, onUnauthorized: onUnauthorized, quiet: false)
    }

    /// Refetch without touching `isLoading`, so the screen does not throw a
    /// full-screen spinner over content the reader is already looking at.
    ///
    /// Called when the share sheet closes, where the only thing that can have
    /// changed is which groups the track is in. A failure is swallowed on
    /// purpose: what is on screen is still valid, merely possibly missing a
    /// share from a moment ago, and an error alert thrown over a working
    /// screen would be the worse outcome.
    func refreshQuietly(
        id: String,
        token: String,
        onUnauthorized: @Sendable @escaping () async -> Void
    ) async {
        await fetch(id: id, token: token, onUnauthorized: onUnauthorized, quiet: true)
    }

    private func fetch(
        id: String,
        token: String,
        onUnauthorized: @Sendable @escaping () async -> Void,
        quiet: Bool
    ) async {
        let api = ListenerAPI(
            client: client,
            tokenProvider: { token },
            onUnauthorized: onUnauthorized
        )

        do {
            detail = try await api.historyDetail(id: id)
        } catch APIError.unauthorized {
            // Sign-out fired by the API actor; clear local state.
            if !quiet { detail = nil }
        } catch {
            if !quiet { errorMessage = mapErrorMessage(for: error) }
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func mapErrorMessage(for error: Error) -> String {
        switch error {
        case APIError.network:
            return "Couldn't reach MixMates. Check your connection."
        case APIError.rateLimited:
            return "Too many requests. Wait a moment and try again."
        default:
            return "Couldn't load this track. Try again."
        }
    }
}

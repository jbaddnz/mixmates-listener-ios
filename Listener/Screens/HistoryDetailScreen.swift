//
//  HistoryDetailScreen.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import Combine
import SwiftUI

/// Detail view for a single saved history item. Loads the detail and the
/// list of groups in parallel on appear, preselects groups the track is
/// already shared to, and lets the user toggle the selection and post the
/// share request.
///
/// Layout follows the Android sibling's `HistoryDetailScreen.kt`:
/// - `TrackCard` at the top (the same component used by `ListenScreen`)
/// - Read-only "Shared to" section listing existing shares
/// - "Share to groups" multi-select with per-group result strings after a
///   successful share
struct HistoryDetailScreen: View {

    let id: String

    @EnvironmentObject private var auth: AuthState
    @StateObject private var viewModel = HistoryDetailViewModel()

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
                TrackCard(detail: detail)

                if !detail.sharedTo.isEmpty {
                    Divider()
                    sharedToSection(groups: detail.sharedTo)
                }

                if !viewModel.groups.isEmpty {
                    Divider()
                    shareToGroupsSection
                }
            }
            .padding()
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

    private var shareToGroupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Share to groups")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.groups) { group in
                    Button {
                        viewModel.toggleGroup(group.id)
                    } label: {
                        let isSelected = viewModel.selectedGroupIds.contains(group.id)
                        HStack(spacing: 12) {
                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                // The ternary can't directly unify `.tint` (`TintShapeStyle`)
                                // with `.secondary` (`HierarchicalShapeStyle`), so coerce
                                // both branches to `Color` which is uniformly typed.
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            Text(group.name)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                Task { await share() }
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

    private func displayStatus(for result: ShareResult) -> String {
        let groupName = viewModel.groups.first(where: { $0.id == result.groupId })?.name ?? result.groupId
        switch result.status {
        case .shared:
            return "Shared to \(groupName)"
        case .duplicate:
            return "Already in \(groupName)!"
        case .other(let status):
            return "\(groupName): \(status)"
        }
    }

    private func load() async {
        guard let token = auth.token else { return }
        await viewModel.load(
            id: id,
            token: token,
            onUnauthorized: { @MainActor in auth.signOut() }
        )
    }

    private func share() async {
        guard let token = auth.token else { return }
        await viewModel.share(
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

/// View model for `HistoryDetailScreen`. Loads the history detail and the
/// available groups in parallel, manages the share-to-groups selection, and
/// posts the share request.
///
/// `import Combine` is required because Xcode 26's `MemberImportVisibility`
/// upcoming feature no longer implicitly re-exports Combine through SwiftUI.
@MainActor
final class HistoryDetailViewModel: ObservableObject {

    @Published private(set) var detail: HistoryDetail?
    @Published private(set) var groups: [HumanGroup] = []
    @Published private(set) var selectedGroupIds: Set<String> = []
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var isSharing: Bool = false
    @Published private(set) var shareResults: [ShareResult]?
    @Published private(set) var errorMessage: String?

    private let client: HTTPClient

    init(client: HTTPClient = URLSession.shared) {
        self.client = client
    }

    /// Fetch the detail and the user's groups in parallel. Both must succeed
    /// for the screen to enter its loaded state — if either fails the user
    /// sees a full-screen error with retry, matching the Android sibling's
    /// all-or-nothing semantics.
    func load(
        id: String,
        token: String,
        onUnauthorized: @Sendable @escaping () async -> Void
    ) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let api = ListenerAPI(
            client: client,
            tokenProvider: { token },
            onUnauthorized: onUnauthorized
        )

        do {
            async let detailFetch = api.historyDetail(id: id)
            async let groupsFetch = api.groups()

            let (loadedDetail, loadedGroups) = try await (detailFetch, groupsFetch)

            self.detail = loadedDetail
            self.groups = loadedGroups
            self.selectedGroupIds = Set(loadedDetail.sharedTo.map { $0.groupId })
        } catch APIError.unauthorized {
            // Sign-out fired by API actor; clear local state.
            self.detail = nil
            self.groups = []
            self.selectedGroupIds = []
        } catch {
            self.errorMessage = mapErrorMessage(for: error)
        }
    }

    /// Toggle a group's selection. Also clears any stale `shareResults` so
    /// the user doesn't see "Shared to X" copy next to a checkbox they just
    /// changed.
    func toggleGroup(_ id: String) {
        if selectedGroupIds.contains(id) {
            selectedGroupIds.remove(id)
        } else {
            selectedGroupIds.insert(id)
        }
        if shareResults != nil {
            shareResults = nil
        }
    }

    /// Post the share. No-ops if there's nothing to share or no detail
    /// loaded. On success stores the per-group results so the screen can
    /// render the "Already in X!" / "Shared to X" status strings.
    func share(
        token: String,
        onUnauthorized: @Sendable @escaping () async -> Void
    ) async {
        guard let detail, !selectedGroupIds.isEmpty else { return }
        isSharing = true
        errorMessage = nil
        defer { isSharing = false }

        let api = ListenerAPI(
            client: client,
            tokenProvider: { token },
            onUnauthorized: onUnauthorized
        )

        do {
            let outcome = try await api.shareHistory(
                id: detail.id,
                groupIds: Array(selectedGroupIds)
            )
            self.shareResults = outcome.results
        } catch APIError.unauthorized {
            // Already handled by callback.
        } catch APIError.groupLocked {
            self.errorMessage = "This group is no longer accepting new tracks"
        } catch {
            self.errorMessage = "Couldn't share — try again"
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

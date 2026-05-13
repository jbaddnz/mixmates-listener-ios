//
//  HistoryScreen.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import Combine
import SwiftUI

/// Paginated history of recognised tracks.
///
/// Loads the first page on appear, supports pull-to-refresh, infinite-scroll
/// pagination via the cursor returned in the previous response, and
/// swipe-to-delete on each row. Tapping a row pushes `HistoryDetailScreen`.
///
/// Swipe-to-delete is a deliberate iOS-idiom deviation from the Android
/// sibling, which uses a per-row trailing delete `IconButton`. Swipe is the
/// native iOS list affordance and `.swipeActions` ships free with `List`.
struct HistoryScreen: View {

    @EnvironmentObject private var auth: AuthState
    @StateObject private var viewModel = HistoryViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                loadingView
            } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
                errorView(message: error)
            } else if viewModel.items.isEmpty {
                emptyView
            } else {
                listView
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadInitial() }
        .refreshable { await loadInitial() }
        .alert(
            "Something went wrong",
            isPresented: errorAlertBinding,
            presenting: viewModel.errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .safeAreaInset(edge: .bottom) {
            MixMatesLinkFooter()
        }
    }

    // MARK: - Sub views

    private var loadingView: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No tracks yet")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadInitial() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listView: some View {
        List {
            ForEach(viewModel.items) { item in
                NavigationLink {
                    HistoryDetailScreen(id: item.id)
                } label: {
                    HistoryRow(item: item)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await delete(id: item.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .onAppear {
                    // Load-more trigger: when the last row appears, ask for
                    // the next page. Gating happens inside `loadMore` so we
                    // can't fire duplicate requests.
                    if item.id == viewModel.items.last?.id {
                        Task { await loadMore() }
                    }
                }
            }
            if viewModel.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Actions

    private func loadInitial() async {
        guard let token = auth.token else { return }
        await viewModel.load(
            token: token,
            onUnauthorized: { @MainActor in auth.signOut() }
        )
    }

    private func loadMore() async {
        guard let token = auth.token else { return }
        await viewModel.loadMore(
            token: token,
            onUnauthorized: { @MainActor in auth.signOut() }
        )
    }

    private func delete(id: String) async {
        guard let token = auth.token else { return }
        await viewModel.delete(
            id: id,
            token: token,
            onUnauthorized: { @MainActor in auth.signOut() }
        )
    }

    /// Two-way binding that surfaces `errorMessage` as an alert and clears
    /// it when the user dismisses. Needed because `errorMessage` is
    /// `@Published private(set)` so we can't bind to it directly.
    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.clearError() }
            }
        )
    }
}

// MARK: - Row

private struct HistoryRow: View {
    let item: HistoryItem

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(1)
                Text(item.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(item.createdAt, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = item.thumbnail {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                placeholderTile
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            placeholderTile
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var placeholderTile: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - View model

/// View model for `HistoryScreen`. Holds the list state plus the in-flight
/// flags for the various network operations the screen can perform.
///
/// Uses individual `@Published` flags rather than a single state enum because
/// the screen has legitimate combinations the enum can't model — "loaded
/// with items but loading more", "loaded but a delete just failed", "loaded
/// but pull-to-refreshing". This shape mirrors the Android sibling's
/// `HistoryUiState` data class.
///
/// `import Combine` is required because Xcode 26's `MemberImportVisibility`
/// upcoming feature no longer implicitly re-exports Combine through SwiftUI.
@MainActor
final class HistoryViewModel: ObservableObject {

    @Published private(set) var items: [HistoryItem] = []
    @Published private(set) var cursor: String?
    @Published private(set) var hasMore: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingMore: Bool = false
    @Published private(set) var errorMessage: String?

    private let client: HTTPClient

    init(client: HTTPClient = URLSession.shared) {
        self.client = client
    }

    /// Initial load and pull-to-refresh both call this. Replaces the items
    /// list and resets pagination state.
    func load(
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
            let page = try await api.history()
            self.items = page.items
            self.cursor = page.cursor
            self.hasMore = page.hasMore
        } catch APIError.unauthorized {
            // The api has already invoked onUnauthorized, which signs the
            // user out. Reset our local state so when the user signs back
            // in no stale items are shown.
            self.items = []
            self.cursor = nil
            self.hasMore = false
        } catch {
            self.errorMessage = mapErrorMessage(for: error)
        }
    }

    /// Append the next page if there is one. No-ops when there's no cursor,
    /// no more results, or another `loadMore` is already in flight.
    /// Pagination failures are deliberately swallowed — surfacing them
    /// would interrupt scroll, which is worse than the user not seeing the
    /// next page until they retry.
    func loadMore(
        token: String,
        onUnauthorized: @Sendable @escaping () async -> Void
    ) async {
        guard let cursor, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let api = ListenerAPI(
            client: client,
            tokenProvider: { token },
            onUnauthorized: onUnauthorized
        )

        do {
            let page = try await api.history(cursor: cursor)
            self.items.append(contentsOf: page.items)
            self.cursor = page.cursor
            self.hasMore = page.hasMore
        } catch APIError.unauthorized {
            // Callback already fired by the API actor; sign-out resets state.
        } catch {
            // Pagination failures are quiet — keep the existing items visible.
        }
    }

    /// Optimistically remove the row from the list. If the delete request
    /// fails, restore the item at its original index and surface a transient
    /// error message via `errorMessage`.
    func delete(
        id: String,
        token: String,
        onUnauthorized: @Sendable @escaping () async -> Void
    ) async {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: index)

        let api = ListenerAPI(
            client: client,
            tokenProvider: { token },
            onUnauthorized: onUnauthorized
        )

        do {
            try await api.deleteHistory(id: id)
        } catch APIError.unauthorized {
            // Callback fired by the API actor; sign-out resets state. Don't
            // restore — the list is about to be torn down anyway.
        } catch {
            self.items.insert(removed, at: index)
            self.errorMessage = "Couldn't remove — try again"
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
            return "Couldn't load your history. Try again."
        }
    }
}

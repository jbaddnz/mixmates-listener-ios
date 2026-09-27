//
//  TrackShareSheet.swift
//  Listener
//

import Combine
import SwiftUI

/// The app's single sharing surface, presented as a sheet from the
/// recognition result and from Track Details.
///
/// Groups come first and the system share sheet sits below a divider,
/// inverting the hierarchy the app shipped through 1.3. Sharing a track's
/// public link is off-platform; sharing it into a MixMates group is the
/// product's thesis, and recognition is the moment of peak motivation. The
/// old arrangement made the off-platform action a one-tap hero and buried
/// group sharing four taps away on another screen.
///
/// Lives in `Screens/` rather than `Components/` because it owns a view
/// model and async state. Every file in `Components/` is a pure view; the
/// view-plus-view-model-in-one-file convention belongs to `Screens/`, and a
/// modal destination with its own loading and error states is screen-like
/// even though it is not pushed onto a navigation stack.
struct TrackShareSheet: View {

    /// Nil when the recognition produced no saved history row, in which case
    /// there is nothing to share into a group and only the system share row
    /// is offered.
    let historyId: String?

    /// Nil for a `noLinks` result: the track was identified but has no
    /// public URL, so the system share row is omitted and groups stand alone.
    let shareURL: URL?

    /// Group ids this track has already been shared to, preselected on open.
    /// Empty from the recognition result, populated from Track Details.
    var alreadySharedTo: [String] = []

    @EnvironmentObject private var auth: AuthState
    @EnvironmentObject private var pushManager: PushManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = TrackShareViewModel()
    @State private var showNotificationAsk = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if historyId != nil {
                        groupsSection
                    }

                    if shareURL != nil {
                        if historyId != nil {
                            Divider()
                        }
                        systemShareRow
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .presentationDetents([.medium, .large])
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Share")
                .font(.title3.weight(.semibold))
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Groups

    @ViewBuilder
    private var groupsSection: some View {
        switch viewModel.groupsState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)

        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                Text("Couldn't load your groups")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Try again") {
                    Task { await load() }
                }
                .font(.callout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .loaded(let groups) where groups.isEmpty:
            emptyState

        case .loaded(let groups):
            if let results = viewModel.shareResults {
                shareSuccessState(results: results, groups: groups)
            } else {
                picker(groups: groups)
            }
        }
    }

    /// Shown when the account is in no groups at all.
    ///
    /// Deliberately a slot rather than a sentence buried in the picker: the
    /// planned in-app group creation replaces this with a "Start a group"
    /// affordance, and nothing else about the sheet needs to change when it
    /// does. Copy stands alone with no reference to any other surface.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No groups yet")
                .font(.callout.weight(.semibold))
            Text("Once you're in a group, your finds can go straight to it from here.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func picker(groups: [HumanGroup]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Share to groups")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(groups) { group in
                    Button {
                        viewModel.toggleGroup(group.id)
                    } label: {
                        let isSelected = viewModel.selectedGroupIds.contains(group.id)
                        HStack(spacing: 12) {
                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                // The ternary can't unify `.tint` with
                                // `.secondary`, so coerce both to `Color`.
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

            if let error = viewModel.shareError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    /// What the sheet shows once a share has landed.
    ///
    /// Its own view on purpose. This is the moment the notifications
    /// permission ask is meant to ride, and the moment group invites will
    /// hang off later; both want somewhere to live that is not tangled into
    /// the picker.
    private func shareSuccessState(results: [ShareResult], groups: [HumanGroup]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(results, id: \.groupId) { result in
                Label(
                    displayStatus(for: result, groups: groups),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            // The track is now somewhere other people will see it, which is
            // the first moment a notification means anything to this person.
            if showNotificationAsk {
                NotificationAskCard(
                    onTurnOn: {
                        showNotificationAsk = false
                        Task { await pushManager.requestPermission() }
                    },
                    onNotNow: { showNotificationAsk = false }
                )
                .padding(.top, 4)
            }

            Button("Share somewhere else") {
                viewModel.resetShareResults()
            }
            .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.default, value: showNotificationAsk)
    }

    // MARK: - System share

    @ViewBuilder
    private var systemShareRow: some View {
        if let shareURL {
            ShareLink(item: shareURL) {
                Label("More ways to share…", systemImage: "square.and.arrow.up")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Helpers

    private func displayStatus(for result: ShareResult, groups: [HumanGroup]) -> String {
        let name = groups.first(where: { $0.id == result.groupId })?.name ?? result.groupId
        switch result.status {
        case .shared:
            return "Shared to \(name)"
        case .duplicate:
            return "Already in \(name)"
        case .other(let status):
            return "\(name): \(status)"
        }
    }

    private func load() async {
        guard let token = auth.token else { return }
        await viewModel.load(
            preselecting: alreadySharedTo,
            token: token,
            onUnauthorized: { @MainActor in auth.signOut() }
        )
    }

    private func share() async {
        guard let token = auth.token, let historyId else { return }
        await viewModel.share(
            historyId: historyId,
            token: token,
            onUnauthorized: { @MainActor in auth.signOut() }
        )
        guard viewModel.shareResults != nil else { return }
        await offerNotificationsIfThisIsTheMoment()
    }

    /// Raise the pre-permission card once a track has actually landed in a
    /// group, which is the point at which somebody else can add to it and
    /// there is finally something worth being told about.
    ///
    /// Unlike the sign-in trigger this has no event flag to consume. The
    /// shown-once record in `NotificationAskPolicy` is what stops it
    /// repeating, and it is shared with the sign-in trigger so between them
    /// they ask a total of once.
    private func offerNotificationsIfThisIsTheMoment() async {
        await pushManager.refreshPermissionStatus()

        guard NotificationAskPolicy.shouldAsk(
            status: pushManager.permissionStatus,
            alreadyAsked: NotificationAskPolicy.hasBeenAsked(),
            trigger: .firstShareSucceeded
        ) else { return }

        NotificationAskPolicy.recordAsked()
        showNotificationAsk = true
    }
}

// MARK: - View model

/// Owns the group list, the selection, and the share call for
/// `TrackShareSheet`.
///
/// `import Combine` is required because Xcode 26's `MemberImportVisibility`
/// upcoming feature no longer implicitly re-exports Combine through SwiftUI.
@MainActor
final class TrackShareViewModel: ObservableObject {

    /// Unloaded and empty are different things and must render differently.
    /// A failed fetch showing "No groups yet" would tell someone with ten
    /// groups that they have none, and in the planned creation flow it would
    /// offer to make another one on top of the ones they already have.
    enum GroupsState: Equatable {
        case loading
        case loaded([HumanGroup])
        case failed
    }

    @Published private(set) var groupsState: GroupsState = .loading
    @Published private(set) var selectedGroupIds: Set<String> = []
    @Published private(set) var isSharing: Bool = false
    @Published private(set) var shareResults: [ShareResult]?
    @Published private(set) var shareError: String?

    private let client: HTTPClient

    init(client: HTTPClient = URLSession.shared) {
        self.client = client
    }

    /// Fetch the account's groups and preselect the ones this track is
    /// already in.
    ///
    /// The preselection is **intersected with the groups actually returned**.
    /// Without that, a group the track was shared to but which no longer
    /// comes back from the server stays silently selected: nothing is ticked
    /// on screen, yet Share is enabled and posts a stale id, and the result
    /// line has no name to resolve so it renders a raw identifier at the
    /// user. That was a live defect in the Track Details screen this sheet
    /// replaces.
    func load(
        preselecting alreadySharedTo: [String],
        token: String,
        onUnauthorized: @Sendable @escaping () async -> Void
    ) async {
        groupsState = .loading

        let api = ListenerAPI(
            client: client,
            tokenProvider: { token },
            onUnauthorized: onUnauthorized
        )

        do {
            let groups = try await api.groups()
            let available = Set(groups.map(\.id))
            groupsState = .loaded(groups)
            selectedGroupIds = Set(alreadySharedTo).intersection(available)
        } catch APIError.unauthorized {
            // Sign-out already fired from the API actor.
            groupsState = .failed
        } catch {
            groupsState = .failed
        }
    }

    func toggleGroup(_ id: String) {
        if selectedGroupIds.contains(id) {
            selectedGroupIds.remove(id)
        } else {
            selectedGroupIds.insert(id)
        }
        shareError = nil
    }

    /// Post the share. No-ops when nothing is selected.
    func share(
        historyId: String,
        token: String,
        onUnauthorized: @Sendable @escaping () async -> Void
    ) async {
        guard !selectedGroupIds.isEmpty else { return }
        isSharing = true
        shareError = nil
        defer { isSharing = false }

        let api = ListenerAPI(
            client: client,
            tokenProvider: { token },
            onUnauthorized: onUnauthorized
        )

        do {
            let outcome = try await api.shareHistory(
                id: historyId,
                groupIds: Array(selectedGroupIds)
            )
            shareResults = outcome.results
        } catch APIError.unauthorized {
            // Already handled by the callback.
        } catch APIError.groupLocked {
            shareError = "This group is no longer accepting new tracks"
        } catch {
            shareError = "Couldn't share. Try again."
        }
    }

    /// Return from the post-share state to the picker.
    func resetShareResults() {
        shareResults = nil
    }
}

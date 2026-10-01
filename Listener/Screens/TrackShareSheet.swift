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

    /// Called with the updated profile when the person sets a display name
    /// from inside this sheet, so a presenter that shows the name can show
    /// the new one without fetching it again.
    var onNameChosen: (UserProfile) -> Void = { _ in }

    @EnvironmentObject private var auth: AuthState
    @EnvironmentObject private var pushManager: PushManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = TrackShareViewModel()
    @State private var showNotificationAsk = false
    @State private var nameDraft = ""
    @State private var groupNameDraft = ""
    @FocusState private var isGroupNameFocused: Bool

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

        case .failed(let message, let retryable):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if retryable {
                    Button("Try again") {
                        Task { await load() }
                    }
                    .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .loaded(let list):
            loadedSection(list)
        }
    }

    @ViewBuilder
    private func loadedSection(_ list: GroupList) -> some View {
        if let results = viewModel.shareResults {
            shareSuccessState(results: results, groups: list.groups)
        } else {
            switch viewModel.panel {
            case .askingForName(let refused):
                DisplayNamePrompt(
                    name: $nameDraft,
                    isSaving: viewModel.isSavingName,
                    error: viewModel.nameError,
                    submitLabel: refused == .share ? ShareFlowCopy.nameSubmit : ShareFlowCopy.nameSubmitSave,
                    onSubmit: { Task { await submitName() } },
                    onCancel: { viewModel.cancelNameEntry() }
                )

            case .startingGroup:
                startGroupForm(canCreate: list.canCreate)

            case .groupCreated(let group):
                groupCreatedState(group)

            case .picker:
                if list.groups.isEmpty {
                    if list.canCreate {
                        emptyStartGroup
                    } else {
                        emptyState
                    }
                } else {
                    picker(groups: list.groups, canCreate: list.canCreate)
                }
            }
        }
    }

    /// Shown when the account is in no groups and may not start one.
    /// Copy stands alone with no reference to any other surface.
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

    /// Shown in place of the empty state when the account is in no groups
    /// and the server says it may start one.
    private var emptyStartGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ShareFlowCopy.startGroup)
                .font(.callout.weight(.semibold))
            Text(ShareFlowCopy.startGroupHint)
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(ShareFlowCopy.startGroup) {
                viewModel.startGroup()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func picker(groups: [HumanGroup], canCreate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Share to groups")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(groups) { group in
                    pickerRow(group)
                }

                // The demo group, or a friend's group the person joined,
                // means the list is usually not empty, so Start a group has
                // to sit beside it rather than only in the empty state.
                if canCreate {
                    Button {
                        viewModel.startGroup()
                    } label: {
                        Label(ShareFlowCopy.startGroup, systemImage: "plus.circle")
                    }
                    .padding(.top, 4)
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

    /// One group: the checkbox row, and an Invite icon as its own tap target
    /// when the group has a link to send. The demo group has none, so it
    /// shows no icon.
    private func pickerRow(_ group: HumanGroup) -> some View {
        HStack(spacing: 12) {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let inviteURL = group.inviteURL {
                ShareLink(
                    item: inviteURL,
                    message: Text(ShareFlowCopy.inviteMessage(for: group.name))
                ) {
                    Image(systemName: "person.badge.plus")
                }
                .accessibilityLabel(ShareFlowCopy.inviteAccessibilityLabel(for: group.name))
            }
        }
    }

    // MARK: - Starting a group

    private func startGroupForm(canCreate: Bool) -> some View {
        let canSubmit = canCreate
            && !viewModel.isCreatingGroup
            && HumanGroup.validName(groupNameDraft) != nil

        return VStack(alignment: .leading, spacing: 12) {
            Text(ShareFlowCopy.startGroup)
                .font(.headline)

            TextField(ShareFlowCopy.groupNamePlaceholder, text: $groupNameDraft)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .focused($isGroupNameFocused)
                .disabled(viewModel.isCreatingGroup)
                .onSubmit {
                    if canSubmit { Task { await createGroup() } }
                }
                .onChange(of: groupNameDraft) { newValue in
                    if newValue.count > HumanGroup.nameMaxLength {
                        groupNameDraft = String(newValue.prefix(HumanGroup.nameMaxLength))
                    }
                }

            Button {
                Task { await createGroup() }
            } label: {
                if viewModel.isCreatingGroup {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(ShareFlowCopy.createSubmit)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)

            if let error = viewModel.createError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(ShareFlowCopy.createCancel) {
                viewModel.cancelStartGroup()
            }
            .font(.callout)
            .disabled(viewModel.isCreatingGroup)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { isGroupNameFocused = true }
    }

    /// The moment after a create. Invite is the next tap rather than a share
    /// sheet opened automatically: `ShareLink` only opens on a tap, and a
    /// system sheet the person did not ask for is the wrong pattern anyway.
    private func groupCreatedState(_ group: HumanGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ShareFlowCopy.groupReady)
                    .font(.headline)
                Text(group.name)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let inviteURL = group.inviteURL {
                ShareLink(
                    item: inviteURL,
                    message: Text(ShareFlowCopy.inviteMessageAfterCreate)
                ) {
                    Label(ShareFlowCopy.inviteAFriend, systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Button(ShareFlowCopy.shareTrackToNewGroup) {
                viewModel.returnToPicker()
            }
            .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the sheet shows once a share has landed.
    ///
    /// Its own view on purpose. This is the moment the notifications
    /// permission ask is meant to ride, and it wants somewhere to live that
    /// is not tangled into the picker.
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

    private func createGroup() async {
        guard let token = auth.token else { return }
        await viewModel.createGroup(
            groupNameDraft,
            token: token,
            onUnauthorized: { @MainActor in auth.signOut() }
        )
    }

    private func submitName() async {
        guard let token = auth.token, let historyId else { return }
        let profile = await viewModel.submitName(
            nameDraft,
            historyId: historyId,
            token: token,
            onUnauthorized: { @MainActor in auth.signOut() }
        )
        if let profile {
            onNameChosen(profile)
        }
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
    /// groups that they have none, and could offer Start a group to an
    /// account the server would refuse.
    ///
    /// A failure also says whether trying again can help. A disabled account
    /// fails the same way every time, and a Try again button under it would
    /// be a promise the app cannot keep.
    ///
    /// Start a group renders only from `.loaded` with `canCreate` true, so a
    /// failed or unfinished fetch can never offer it.
    enum GroupsState: Equatable {
        case loading
        case loaded(GroupList)
        case failed(message: String, retryable: Bool)
    }

    /// What the loaded groups section shows, when it is not showing the
    /// outcome of a share.
    enum Panel: Equatable {
        case picker
        /// The field for naming a new group.
        case startingGroup
        /// The display-name prompt, and what to retry once the name is saved.
        case askingForName(then: RefusedAction)
        /// The moment after a create, with Invite as the next tap.
        case groupCreated(HumanGroup)
    }

    /// The action a missing display name refused, held so it can be retried
    /// without the person starting it again.
    enum RefusedAction: Equatable {
        case share
        case createGroup(name: String)
    }

    @Published private(set) var groupsState: GroupsState = .loading
    @Published private(set) var selectedGroupIds: Set<String> = []
    @Published private(set) var isSharing: Bool = false
    @Published private(set) var shareResults: [ShareResult]?
    @Published private(set) var shareError: String?
    @Published private(set) var panel: Panel = .picker

    @Published private(set) var isSavingName: Bool = false
    @Published private(set) var nameError: String?

    @Published private(set) var isCreatingGroup: Bool = false
    @Published private(set) var createError: String?

    /// True while the display-name prompt is up. The selection is kept, so a
    /// refused share can be retried without starting over.
    var isAskingForName: Bool {
        if case .askingForName = panel { return true }
        return false
    }

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
            let list = try await api.groups()
            let available = Set(list.groups.map(\.id))
            groupsState = .loaded(list)
            selectedGroupIds = Set(alreadySharedTo).intersection(available)
        } catch APIError.listenDisabled {
            groupsState = .failed(message: ShareFlowCopy.listenDisabled, retryable: false)
        } catch {
            // Includes 401, where sign-out has already fired from the API
            // actor and the sheet is about to go away.
            groupsState = .failed(message: ShareFlowCopy.couldNotLoadGroups, retryable: true)
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
        await performShare(
            historyId: historyId,
            token: token,
            onUnauthorized: onUnauthorized,
            mayAskForName: true
        )
    }

    /// Save a display name after a share or a create was refused for want of
    /// one, then retry the refused action once.
    ///
    /// Returns the updated profile so the caller can refresh anything that
    /// shows the name, or nil when the name was not saved. The retry may not
    /// ask for a name again: if the server still refuses, something other
    /// than the name is wrong and looping would hide it.
    func submitName(
        _ input: String,
        historyId: String,
        token: String,
        onUnauthorized: @Sendable @escaping () async -> Void
    ) async -> UserProfile? {
        guard let name = UserProfile.validDisplayName(input) else { return nil }
        isSavingName = true
        nameError = nil
        defer { isSavingName = false }

        let api = makeAPI(token: token, onUnauthorized: onUnauthorized)
        let profile: UserProfile
        do {
            profile = try await api.updateDisplayName(name)
        } catch APIError.unauthorized {
            return nil
        } catch {
            nameError = ShareFlowCopy.nameSaveFailure(error)
            return nil
        }

        guard case .askingForName(let refused) = panel else { return profile }
        switch refused {
        case .share:
            panel = .picker
            await performShare(
                historyId: historyId,
                token: token,
                onUnauthorized: onUnauthorized,
                mayAskForName: false
            )
        case .createGroup(let name):
            panel = .startingGroup
            await performCreate(
                name: name,
                token: token,
                onUnauthorized: onUnauthorized,
                mayAskForName: false
            )
        }
        return profile
    }

    /// Leave the name prompt and go back to where the refused action started:
    /// the picker with its selection, or the group-name field.
    func cancelNameEntry() {
        if case .askingForName(.createGroup) = panel {
            panel = .startingGroup
        } else {
            panel = .picker
        }
        nameError = nil
    }

    // MARK: Starting a group

    func startGroup() {
        panel = .startingGroup
        createError = nil
    }

    func cancelStartGroup() {
        panel = .picker
        createError = nil
    }

    /// From the created-group moment back to the picker, where the new group
    /// is already ticked.
    func returnToPicker() {
        panel = .picker
    }

    /// Create a group with this name. A blank or over-long name sends
    /// nothing.
    func createGroup(
        _ input: String,
        token: String,
        onUnauthorized: @Sendable @escaping () async -> Void
    ) async {
        guard let name = HumanGroup.validName(input) else { return }
        await performCreate(
            name: name,
            token: token,
            onUnauthorized: onUnauthorized,
            mayAskForName: true
        )
    }

    private func performCreate(
        name: String,
        token: String,
        onUnauthorized: @Sendable @escaping () async -> Void,
        mayAskForName: Bool
    ) async {
        isCreatingGroup = true
        createError = nil
        defer { isCreatingGroup = false }

        let api = makeAPI(token: token, onUnauthorized: onUnauthorized)

        do {
            let group = try await api.createGroup(name: name)
            await refreshGroupsInPlace(api: api, created: group)
            selectedGroupIds.insert(group.id)
            panel = .groupCreated(group)
        } catch APIError.unauthorized {
            // Already handled by the callback.
        } catch APIError.nameRequired where mayAskForName {
            panel = .askingForName(then: .createGroup(name: name))
        } catch APIError.alreadyHasGroup {
            // The list was stale. Re-read it so can_create comes back false
            // and Start a group goes away.
            createError = ShareFlowCopy.alreadyHasGroup
            await refreshGroupsInPlace(api: api, created: nil)
        } catch {
            createError = ShareFlowCopy.createFailure(error)
        }
    }

    /// Re-read the groups without passing through `.loading`, so the sheet
    /// does not flash a spinner between states.
    ///
    /// After a create, the new group certainly exists, so if the re-read
    /// fails or lags it is added to what is on screen, and `canCreate` drops
    /// to false because the account now owns a group. That is the server's
    /// own rule, applied to an answer it has just given.
    private func refreshGroupsInPlace(api: ListenerAPI, created: HumanGroup?) async {
        var list: GroupList
        do {
            list = try await api.groups()
        } catch {
            guard let created, case .loaded(let current) = groupsState else { return }
            list = GroupList(groups: current.groups, canCreate: false)
        }
        if let created, !list.groups.contains(where: { $0.id == created.id }) {
            list = GroupList(groups: list.groups + [created], canCreate: false)
        }
        groupsState = .loaded(list)
        selectedGroupIds.formIntersection(list.groups.map(\.id))
    }

    private func performShare(
        historyId: String,
        token: String,
        onUnauthorized: @Sendable @escaping () async -> Void,
        mayAskForName: Bool
    ) async {
        isSharing = true
        shareError = nil
        defer { isSharing = false }

        let api = makeAPI(token: token, onUnauthorized: onUnauthorized)

        do {
            let outcome = try await api.shareHistory(
                id: historyId,
                groupIds: Array(selectedGroupIds)
            )
            shareResults = outcome.results
        } catch APIError.unauthorized {
            // Already handled by the callback.
        } catch APIError.nameRequired where mayAskForName {
            panel = .askingForName(then: .share)
        } catch APIError.notGroupMember {
            // Reload so the group they left drops out of the picker and out
            // of the selection, and Share does not post it again.
            shareError = ShareFlowCopy.notGroupMember
            await load(
                preselecting: Array(selectedGroupIds),
                token: token,
                onUnauthorized: onUnauthorized
            )
        } catch {
            shareError = ShareFlowCopy.shareFailure(error)
        }
    }

    private func makeAPI(
        token: String,
        onUnauthorized: @Sendable @escaping () async -> Void
    ) -> ListenerAPI {
        ListenerAPI(client: client, tokenProvider: { token }, onUnauthorized: onUnauthorized)
    }

    /// Return from the post-share state to the picker.
    func resetShareResults() {
        shareResults = nil
    }
}

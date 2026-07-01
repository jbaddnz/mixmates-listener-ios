//
//  SettingsScreen.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import Combine
import SwiftUI
import UIKit

/// Settings screen, iOS-native `Form` layout. Sections ordered actions
/// first, info/reference next, destructive account deletion at the very
/// bottom:
/// - **Notifications**: push permission state and enable/manage controls.
/// - **Sign out**: destructive, local-only — clears the Keychain entry.
/// - **Share Extension**: a tip on pinning the extension in the share sheet.
/// - **Legal**: navigates to `LegalScreen` (privacy, terms, trademarks,
///   about, version).
/// - **Delete account**: destructive, calls the in-app delete endpoint,
///   wipes the Keychain, drops the user to signed-out. Required by App
///   Store Review Guideline 5.1.1(v).
struct SettingsScreen: View {

    @EnvironmentObject private var auth: AuthState
    @EnvironmentObject private var pushManager: PushManager
    @Environment(\.openURL) private var openURL
    @StateObject private var deleteViewModel = DeleteAccountViewModel()
    @State private var showRemoveConfirmation = false
    @State private var showDeleteAccountConfirmation = false
    @State private var showDeleteErrorAlert = false

    var body: some View {
        Form {
            Section {
                Group {
                    switch pushManager.permissionStatus {
                    case .notDetermined:
                        Button("Enable group notifications") {
                            Task { await pushManager.requestPermission() }
                        }
                    case .authorized:
                        HStack {
                            Label("Group notifications enabled", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Button("Manage") {
                                openURL(URL(string: UIApplication.openSettingsURLString)!)
                            }
                            .font(.callout)
                        }
                    case .denied:
                        Button("Enable in Settings") {
                            openURL(URL(string: UIApplication.openSettingsURLString)!)
                        }
                    default:
                        EmptyView()
                    }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Get notified when someone shares a track to your groups.")
            }

            Section {
                Button(role: .destructive) {
                    showRemoveConfirmation = true
                } label: {
                    Text("Sign out")
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                Text("Signs you out of this device. Your MixMates account stays active.")
            }

            Section("Share Extension") {
                Text("To pin MixMates Listener to the top of your share sheet, open the share sheet in any app, scroll right, tap More, then tap Edit and add MixMates Listener to your favourites.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                NavigationLink("Legal", destination: LegalScreen())
            }

            Section {
                Button(role: .destructive) {
                    showDeleteAccountConfirmation = true
                } label: {
                    if deleteViewModel.isDeleting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Delete account")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(deleteViewModel.isDeleting)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Sign out?", isPresented: $showRemoveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Sign out", role: .destructive) {
                Task {
                    await pushManager.deregister()
                    auth.signOut()
                }
            }
        } message: {
            Text("You'll need to sign in again to use the app.")
        }
        .alert("Delete your account?", isPresented: $showDeleteAccountConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("Deleting permanently removes your account, recognition history, and all associated data. This cannot be undone.")
        }
        .alert("Couldn't delete account", isPresented: $showDeleteErrorAlert, presenting: deleteViewModel.errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private func deleteAccount() async {
        guard let token = auth.token else { return }
        let succeeded = await deleteViewModel.delete(
            token: token,
            onUnauthorized: { @MainActor in auth.signOut() }
        )
        if succeeded {
            await pushManager.deregister()
            auth.signOut()
        } else if deleteViewModel.errorMessage != nil {
            showDeleteErrorAlert = true
        }
    }
}

/// View model for the delete-account flow. Owns the network call and its
/// loading/error state; the view drives sign-out on success.
///
/// `@MainActor` because it drives a SwiftUI view. `ObservableObject` rather
/// than `@Observable` because the deployment target is iOS 16.
@MainActor
final class DeleteAccountViewModel: ObservableObject {

    @Published private(set) var isDeleting = false
    @Published var errorMessage: String?

    private let client: HTTPClient
    private let baseURL: URL

    init(client: HTTPClient = URLSession.shared,
         baseURL: URL = ListenerAPI.defaultBaseURL) {
        self.client = client
        self.baseURL = baseURL
    }

    /// Call `DELETE /account`. Returns `true` on success so the view can
    /// clear the keychain and drop to signed-out. On `401` the auth
    /// callback fires (already signs out); the view treats that as a
    /// no-op. Other failures set `errorMessage`.
    func delete(token: String, onUnauthorized: @Sendable @escaping () async -> Void) async -> Bool {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        let api = ListenerAPI(
            baseURL: baseURL,
            client: client,
            tokenProvider: { token },
            onUnauthorized: onUnauthorized
        )

        do {
            try await api.deleteAccount()
            return true
        } catch APIError.unauthorized {
            return false
        } catch APIError.network {
            errorMessage = "Couldn't reach MixMates. Check your connection and try again."
        } catch APIError.rateLimited {
            errorMessage = "Too many attempts. Wait a moment and try again."
        } catch {
            errorMessage = "Something went wrong. Try again."
        }
        return false
    }
}

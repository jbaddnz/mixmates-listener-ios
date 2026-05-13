//
//  SettingsScreen.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import SwiftUI
import UIKit

/// Settings screen, iOS-native `Form` layout. Sections ordered actions
/// first, info/reference next, destructive account deletion at the very
/// bottom:
/// - **Account**: opens `AlternateAccountScreen` as a sheet for switching
///   this device to a different MixMates account via Listen Key. Used for
///   venue staff, event volunteers, or operators running multiple accounts
///   on one device.
/// - **Notifications**: push permission state and enable/manage controls.
/// - **Sign out**: destructive, local-only — clears the Keychain entry,
///   the account at mixmat.es is untouched.
/// - **Share Extension**: a tip on pinning the extension in the share sheet.
/// - **Legal**: navigates to `LegalScreen` (privacy, terms, trademarks,
///   about, version).
/// - **Delete account**: destructive, opens `mixmat.es/account/delete` in
///   Safari. Required by App Store Review Guideline 5.1.1(v). The brand
///   footer hangs off this bottom-most section.
///
/// No view model — state is just the alert/sheet visibilities (`@State`).
struct SettingsScreen: View {

    @EnvironmentObject private var auth: AuthState
    @EnvironmentObject private var pushManager: PushManager
    @Environment(\.openURL) private var openURL
    @State private var showRemoveConfirmation = false
    @State private var showDeleteAccountConfirmation = false
    @State private var showAlternateAccountSheet = false

    private static let deleteAccountURL = URL(string: "https://mixmat.es/account/delete")!

    var body: some View {
        Form {
            Section {
                Button {
                    showAlternateAccountSheet = true
                } label: {
                    Text("Switch to another MixMates account")
                }
            } header: {
                Text("Account")
            } footer: {
                Text("Switch this device to a different MixMates account using a Listen Key.")
            }

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
                    Text("Delete account")
                        .frame(maxWidth: .infinity)
                }
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
            Button("Continue", role: .destructive) {
                openURL(Self.deleteAccountURL)
            }
        } message: {
            Text("You'll be taken to mixmat.es to confirm. Deleting permanently removes your account, recognition history, and all associated data. This cannot be undone.")
        }
        .sheet(isPresented: $showAlternateAccountSheet) {
            AlternateAccountScreen()
        }
        .safeAreaInset(edge: .bottom) {
            MixMatesLinkFooter()
        }
    }
}

//
//  SettingsScreen.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import SwiftUI
import UIKit

/// Settings screen. Three sections in an iOS-native `Form` layout:
/// - **Legal**: a `NavigationLink` to `LegalScreen`, which holds the
///   in-app trademark credit line, links to the web-hosted privacy and
///   terms pages, and About info.
/// - **Sign out**: the "Remove Listen Key" destructive action with a
///   confirmation alert. Local-only — clears the Keychain entry, the
///   account at mixmat.es is untouched.
/// - **Delete account**: a destructive action that, after confirmation,
///   opens `mixmat.es/account/delete` in Safari. The web side renders the
///   typed-confirmation modal directly on landing for authenticated users
///   (or after sign-in for anonymous ones). Required by App Store Review
///   Guideline 5.1.1(v) — apps that "support account creation" must offer
///   in-app deletion. The Listener doesn't create accounts (paste-a-key
///   model), but reviewers still flag the absence and Apple's account
///   deletion guidance explicitly allows linking to a web URL when full
///   in-app deletion isn't possible. The brand footer hangs off this
///   bottom-most section.
///
/// No view model — state is just the two alert visibilities (`@State`).
/// The only async action is `auth.signOut()`, reached directly through the
/// `AuthState` environment object. Adding a `SettingsViewModel` would be a
/// one-line wrapper around existing operations, which the project's "no
/// abstractions for one-time things" rule explicitly avoids.
///
/// No display name / role / rate limit display — those live elsewhere.
/// Matches the Android sibling's settings minimalism. There is no theme
/// picker; see `docs/plans/proposed/theme-preference.md` (gitignored) for
/// the rationale.
struct SettingsScreen: View {

    @EnvironmentObject private var auth: AuthState
    @EnvironmentObject private var pushManager: PushManager
    @Environment(\.openURL) private var openURL
    @State private var showRemoveConfirmation = false
    @State private var showDeleteAccountConfirmation = false

    private static let deleteAccountURL = URL(string: "https://mixmat.es/account/delete")!

    var body: some View {
        Form {
            Section {
                NavigationLink("Legal", destination: LegalScreen())
            }

            Section("Share Extension") {
                Text("To pin MixMates Listener to the top of your share sheet, open the share sheet in any app, scroll right, tap More, then tap Edit and add MixMates Listener to your favourites.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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

            Section {
                Button(role: .destructive) {
                    showDeleteAccountConfirmation = true
                } label: {
                    Text("Delete account")
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                brandFooter
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
    }

    private var brandFooter: some View {
        VStack(spacing: 4) {
            Text("MixMates Listener")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link("mixmat.es", destination: URL(string: "https://mixmat.es")!)
                .font(.caption)
            Text("MixMat Ltd")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("v\(appVersion)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}

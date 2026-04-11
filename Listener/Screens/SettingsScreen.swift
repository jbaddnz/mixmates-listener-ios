//
//  SettingsScreen.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import SwiftUI

/// Settings screen. Four sections in an iOS-native `Form` layout:
/// - **Appearance**: a single "Show splash screen" toggle, opt-out for the
///   1-second SwiftUI splash continuation that runs after the OS-level
///   `UILaunchScreen`. Default on.
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
/// No view model — state is just the two alert visibilities (`@State`) and
/// the splash preference (`@AppStorage`, shared with `ContentView`). The
/// only async action is `auth.signOut()`, reached directly through the
/// `AuthState` environment object. Adding a `SettingsViewModel` would be a
/// one-line wrapper around existing operations, which the project's "no
/// abstractions for one-time things" rule explicitly avoids.
///
/// No display name / role / rate limit display — those live elsewhere
/// (rate limit goes in the Listen screen toolbar). Matches the Android
/// sibling's settings minimalism. There is no theme picker; see
/// `docs/plans/proposed/theme-preference.md` (gitignored) for the rationale.
struct SettingsScreen: View {

    @EnvironmentObject private var auth: AuthState
    @Environment(\.openURL) private var openURL
    @AppStorage("showSplashScreen") private var showSplashEnabled: Bool = true
    @State private var showRemoveConfirmation = false
    @State private var showDeleteAccountConfirmation = false

    private static let deleteAccountURL = URL(string: "https://mixmat.es/account/delete")!

    var body: some View {
        Form {
            Section {
                Toggle("Show splash screen", isOn: $showSplashEnabled)
            } footer: {
                Text("Show the MML logo briefly when the app opens. Turn off to skip straight to the listen screen.")
            }

            Section {
                NavigationLink("Legal", destination: LegalScreen())
            }

            Section {
                Button(role: .destructive) {
                    showRemoveConfirmation = true
                } label: {
                    Text("Remove Listen Key")
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                Text("Removes the key from this device. Your account at mixmat.es stays active.")
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
        .alert("Remove Listen Key?", isPresented: $showRemoveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                auth.signOut()
            }
        } message: {
            Text("You'll need to enter it again to use the app.")
        }
        .alert("Delete your account?", isPresented: $showDeleteAccountConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Continue", role: .destructive) {
                openURL(Self.deleteAccountURL)
            }
        } message: {
            Text("You'll be taken to mixmat.es to confirm. Deleting permanently removes your Listen Key, recognition history, and all associated data. This cannot be undone.")
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

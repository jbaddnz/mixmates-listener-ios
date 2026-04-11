//
//  SettingsScreen.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import SwiftUI

/// Settings screen. Two sections in an iOS-native `Form` layout:
/// - **Appearance**: a single "Show splash screen" toggle, opt-out for the
///   1-second SwiftUI splash continuation that runs after the OS-level
///   `UILaunchScreen`. Default on.
/// - **Account**: the "Remove Listen Key" destructive action with a
///   confirmation alert, plus a brand footer crediting the app and linking
///   to the marketing site.
///
/// No view model — the only state is the alert visibility (`@State`) and
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
    @AppStorage("showSplashScreen") private var showSplashEnabled: Bool = true
    @State private var showRemoveConfirmation = false

    var body: some View {
        Form {
            Section {
                Toggle("Show splash screen", isOn: $showSplashEnabled)
            } footer: {
                Text("Show the MML logo briefly when the app opens. Turn off to skip straight to the listen screen.")
            }

            Section {
                Button(role: .destructive) {
                    showRemoveConfirmation = true
                } label: {
                    Text("Remove Listen Key")
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

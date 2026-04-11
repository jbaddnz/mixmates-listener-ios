//
//  SettingsScreen.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import SwiftUI

/// Settings screen. Deliberately minimal: a single "Remove Listen Key"
/// destructive action with a confirmation alert, plus a footer crediting
/// the app and linking to the marketing site.
///
/// No view model — the only state is the alert visibility (`@State`) and the
/// only action is `auth.signOut()`, which is reached directly through the
/// `AuthState` environment object. Adding a `SettingsViewModel` here would
/// be a one-line wrapper around an existing operation, which the project's
/// "no abstractions for one-time things" rule explicitly avoids.
///
/// No rate limit / display name / role display: matches the Android sibling's
/// minimalism. The rate limit indicator surfaces on the Listen screen toolbar
/// instead (deferred to a future slice).
struct SettingsScreen: View {

    @EnvironmentObject private var auth: AuthState
    @State private var showRemoveConfirmation = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Button(role: .destructive) {
                showRemoveConfirmation = true
            } label: {
                Text("Remove Listen Key")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.horizontal)

            Spacer()

            footer
        }
        .padding()
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

    private var footer: some View {
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
        .padding(.bottom)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}

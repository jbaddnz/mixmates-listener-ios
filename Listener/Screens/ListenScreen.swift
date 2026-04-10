//
//  ListenScreen.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import SwiftUI

/// Placeholder ListenScreen. The real implementation (record button, audio
/// recording, recognition flow, history nav, settings nav) lands in a later
/// session — for now this just confirms the signed-in vertical slice works
/// end-to-end by hitting `/auth/me` with the persisted key, and gives the
/// user a way to sign out.
struct ListenScreen: View {

    @EnvironmentObject private var auth: AuthState
    @State private var displayName: String?
    @State private var loadError: String?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            if isLoading {
                ProgressView("Loading…")
            } else if let displayName {
                Text("Welcome, \(displayName).")
                    .font(.title2)
                Text("Recording UI lands in the next session.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let loadError {
                Text(loadError)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button("Sign out", role: .destructive) {
                auth.signOut()
            }
            .buttonStyle(.bordered)
            .padding(.bottom)
        }
        .padding()
        .task { await loadProfile() }
    }

    private func loadProfile() async {
        guard let token = auth.token else {
            isLoading = false
            return
        }
        let api = ListenerAPI(tokenProvider: { token })
        do {
            let profile = try await api.me()
            displayName = profile.displayName
            isLoading = false
        } catch APIError.unauthorized {
            // Token went stale (revoked, expired, listen disabled). Bounce
            // back to TokenEntry. The `onUnauthorized` callback on the
            // shared `ListenerAPI` instance would do this for us in the
            // wider app — for this one-shot probe, we handle it locally.
            auth.signOut()
        } catch {
            loadError = "Couldn't load your profile."
            isLoading = false
        }
    }
}

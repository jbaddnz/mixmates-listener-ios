//
//  TermsScreen.swift
//  Listener
//

import SwiftUI

/// Native in-app rendering of the Listener Terms of Service. The source
/// text is maintained inline so the app contains no outbound links to the
/// MixMates website. The canonical server copy at
/// `mixmat.es/terms/listener` is what ASC's required Privacy Policy URL
/// field and the Android app point at; if the text changes, update both
/// surfaces together.
struct TermsScreen: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Last updated: 3 July 2026")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("These terms cover the MixMates Listener apps for iOS and Android, operated by MixMat Ltd, a New Zealand company.")

                section(
                    "1. The service",
                    "Listener is a free music-recognition app. It records a short audio clip when you ask it to, identifies the song, and shows you public streaming links on Spotify, Tidal, and Apple Music. Your recognition history is saved to your account so you can find songs again."
                )

                section(
                    "2. Free means free",
                    "The Listener app is free. It contains no purchases and no features that unlock. Every authenticated account receives the same functionality and the same usage limits."
                )

                section(
                    "3. Your account",
                    "You sign in with Apple or Google. One person, one account. You can delete your account at any time from inside the app (Settings → Delete account); deletion is immediate and removes your account and its data."
                )

                section(
                    "4. Audio",
                    "When you tap Listen, the app records roughly eleven seconds of audio and sends it to our recognition provider to identify the song. Clips are used only for identification and are not kept, unless you have opted in to saving recordings (see the privacy policy)."
                )

                section(
                    "5. Fair use",
                    "Usage limits apply identically to every account and exist to keep the service healthy. Don't attempt to circumvent them, automate the app, or use it in a way that interferes with anyone else's use."
                )

                section(
                    "6. The usual conditions",
                    "The service is provided as-is; we do our best to keep it accurate and available but can't guarantee either. Nothing in these terms limits rights you have under New Zealand consumer law. These terms are governed by New Zealand law."
                )

                section(
                    "7. Changes",
                    "If we change these terms we'll update this page and the date above."
                )

                HStack(spacing: 4) {
                    Text("MixMat Ltd, New Zealand ·")
                    Link("legal@mixmat.es", destination: URL(string: "mailto:legal@mixmat.es")!)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func section(_ heading: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading)
                .font(.headline)
            Text(body)
        }
    }
}

#Preview {
    NavigationStack { TermsScreen() }
}

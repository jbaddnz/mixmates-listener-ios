//
//  PrivacyScreen.swift
//  Listener
//

import SwiftUI

/// Native in-app rendering of the Listener Privacy Policy. The source
/// text is maintained inline so the app contains no outbound links to the
/// MixMates website. The canonical server copy at
/// `mixmat.es/privacy/listener` is what ASC's required Privacy Policy URL
/// field and the Android app point at; if the text changes, update both
/// surfaces together.
struct PrivacyScreen: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Last updated: 3 October 2026")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("This policy covers the MixMates Listener apps for iOS and Android, operated by MixMat Ltd, a New Zealand company. The New Zealand Privacy Act 2020 is our baseline.")

                sectionHeader("What we collect")
                bullet("Account:", "an identifier from Apple or Google when you sign in, and a display name (the one Apple or Google gives us, or one you choose). Your email address arrives when you sign in, but we do not keep it.")
                bullet("Audio:", "a short clip of up to 12 seconds each time you tap Listen, used solely to identify the song.")
                bullet("History:", "the songs you've recognised, tied to your account so you can revisit them.")
                bullet("Groups:", "the groups you start or join, and the songs you share into them. The members of a group see each other's display names and what each person shared.")
                bullet("Invites:", "when someone joins a group through an invite link for the first time, we record on their account which group it was and who started it.")
                bullet("Saved recordings (opt-in only):", "if you turn on saving, up to five clips are kept for you, each auto-deleted after 30 days. Off by default.")
                bullet("Push token:", "only if you enable notifications.")

                sectionHeader("How audio is handled")
                Text("Clips are sent to our recognition provider, AudD, to identify the song. AudD has committed to us in writing that it does not retain your audio and does not use it to train anything. We don't keep your clips either, unless you've opted in to saved recordings.")

                sectionHeader("What we don't do")
                simpleBullet("No advertising, and no advertising identifiers.")
                simpleBullet("No analytics or tracking SDKs in the apps.")
                simpleBullet("No location collection, no contact access.")
                simpleBullet("No selling of your data, and no behavioural profiling. We pass on only what a feature needs: your clip to our recognition provider, and what you choose to share to the members of your groups.")

                sectionHeader("Retention and deletion")
                Text("Recognition service logs are kept for 30 days for abuse prevention, then deleted. Your history stays until you delete it or your account. Deleting your account (Settings → Delete account, in the app) is immediate and removes your account, history, and any saved recordings. Songs you shared into a group stay there without your name.")

                sectionHeader("Your rights")
                Text("Under the Privacy Act 2020 you can ask for a copy of your information or ask us to correct it. Email us and we'll sort it.")

                sectionHeader("Changes")
                Text("If we change this policy we'll update this page and the date above. If a change means we collect a new kind of personal information, or share it with someone new, we post it here before it takes effect.")

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
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func bullet(_ lead: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text("**\(lead)** \(body)")
        }
    }

    @ViewBuilder
    private func simpleBullet(_ body: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(body)
        }
    }
}

#Preview {
    NavigationStack { PrivacyScreen() }
}

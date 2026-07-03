//
//  LegalScreen.swift
//  Listener
//
//  Created by jamie baddeley on 12/04/2026.
//

import SwiftUI

/// In-app legal copy area, pushed from Settings → Legal. Three sections:
/// - **Policies**: pushes native `PrivacyScreen` / `TermsScreen`. Their
///   text is maintained inline; the app contains no outbound links to
///   the MixMates website.
/// - **Trademarks**: the Apple Music credit line required by section 9.2 of
///   the Apple Music Identity Guidelines, "wherever legal copy is shown."
///   Spotify and Tidal credit lines are deliberately deferred until the
///   exact wording is read from their respective design guidelines —
///   making one up risks being wrong in a way that's worse than absence.
/// - **About**: app version + build, source code link, copyright in the
///   section footer.
///
/// No view model — pure presentation, no state. The version and build
/// number are read from the bundle each time the view appears.
struct LegalScreen: View {

    var body: some View {
        Form {
            Section("Policies") {
                NavigationLink("Privacy Policy") {
                    PrivacyScreen()
                }
                NavigationLink("Terms of Service") {
                    TermsScreen()
                }
            }

            Section("Trademarks") {
                Text("Apple and Apple Music are trademarks of Apple Inc., registered in the U.S. and other countries.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("MixMates Listener is a free music-recognition app. It records audio, identifies songs, and shows public streaming links on Spotify, Tidal, and Apple Music.\n\nNo in-app purchases. No subscription prompts. Every authenticated user has the same features.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                LabeledContent("Version", value: versionString)
                Link(
                    "Source code",
                    destination: URL(string: "https://github.com/jbaddnz/mixmates-listener-ios")!
                )
            } header: {
                Text("About MixMates Listener")
            }
        }
        .navigationTitle("Legal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

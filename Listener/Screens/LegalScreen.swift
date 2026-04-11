//
//  LegalScreen.swift
//  Listener
//
//  Created by jamie baddeley on 12/04/2026.
//

import SwiftUI

/// In-app legal copy area, pushed from Settings → Legal. Three sections:
/// - **Policies**: links to the marketing-site-hosted Privacy Policy and
///   Terms of Service. The web pages are the canonical source.
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
                Link(
                    "Privacy Policy",
                    destination: URL(string: "https://mixmat.es/privacy")!
                )
                Link(
                    "Terms of Service",
                    destination: URL(string: "https://mixmat.es/terms")!
                )
            }

            Section("Trademarks") {
                Text("Apple and Apple Music are trademarks of Apple Inc., registered in the U.S. and other countries.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version", value: versionString)
                Link(
                    "Source code",
                    destination: URL(string: "https://github.com/jbaddnz/mixmates-listener-ios")!
                )
            } header: {
                Text("About")
            } footer: {
                Text("© \(currentYear) MixMat Ltd")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
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

    /// Pulled fresh from `Calendar.current` on every render so the
    /// copyright stays current without anyone needing to remember to
    /// bump it on January 1. Returned as a `String` rather than `Int`
    /// to avoid the locale-aware grouping separator that `Text`
    /// interpolation would otherwise insert (e.g. "2,026").
    private var currentYear: String {
        String(Calendar.current.component(.year, from: Date()))
    }
}

//
//  OpenInMixMatesButton.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import SwiftUI

/// MixMates brand gradient: Spotify-green to cyan, leading-to-trailing.
///
/// Used by `OpenInMixMatesButton` (the call-to-action button on the Listen
/// result and the History detail screen) and the Listen screen mic button
/// background. Lives here as an extension on `LinearGradient` so both call
/// sites have a single source of truth for the brand colours. If a `Theme/`
/// folder is later created (per `CLAUDE.md`'s placeholder), this extension
/// should move there.
extension LinearGradient {
    static let mixmatesBrand = LinearGradient(
        colors: [
            Color(red: 29 / 255, green: 185 / 255, blue: 84 / 255),  // Spotify green
            Color(red: 44 / 255, green: 204 / 255, blue: 211 / 255)  // cyan
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

/// "Open in MixMates" call-to-action button. Deep-links to
/// `https://mixmat.es/?listen=1`.
///
/// Used by both `ListenScreen` (after a recognition result, regardless of
/// status — saved, duplicate, no-match, or no-links) and
/// `HistoryDetailScreen` (under the track card). Mirrors the Android sibling's
/// gradient button shape: full-width, rounded extra-large shape, white text on
/// the brand gradient background, headline font.
///
/// `@Environment(\.openURL)` is used internally so the button has no
/// parameters — call sites just write `OpenInMixMatesButton()`.
struct OpenInMixMatesButton: View {

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(URL(string: "https://mixmat.es/?listen=1")!)
        } label: {
            Text("Open in MixMates")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(LinearGradient.mixmatesBrand)
                .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }
}

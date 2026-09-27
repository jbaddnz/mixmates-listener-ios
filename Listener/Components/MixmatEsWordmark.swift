//
//  MixmatEsWordmark.swift
//  Listener
//

import SwiftUI

/// The mixmat.es wordmark, rendered from the wordmark package
/// (MuseoModerno 700, brand gradient) by the recipe in `assets/mml-wordmark`.
///
/// **Strictly non-tappable, and it must stay that way.** A plain `Image`
/// with no `Link`, no `Button`, no `onTapGesture`, and nothing nearby that
/// could swallow a tap and route somewhere. It is a mark, not a way out of
/// the app, and the distinction is load-bearing rather than stylistic.
///
/// Hidden from accessibility for the same reason: it carries no information
/// and no action, so announcing it would only add noise between the things
/// that do.
struct MixmatEsWordmark: View {

    /// Narrower on the utility screens than on the idle Listen screen,
    /// where it is the only thing in the lower half of the display.
    var width: CGFloat = 116

    var body: some View {
        Image("MixmatEsWordmark")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Mount the wordmark as the last thing in a `Form` or `List`.
    ///
    /// Inside the scroll content rather than pinned to the bottom edge, so
    /// it reads as the end of the page rather than as a persistent bar. That
    /// also avoids needing a background behind it to stop content sliding
    /// underneath.
    @ViewBuilder
    func wordmarkFooterRow() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

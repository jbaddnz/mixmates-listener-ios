//
//  MixMatesLinkFooter.swift
//  Listener
//
//  Created by jamie baddeley on 13/05/2026.
//

import SwiftUI

/// Tappable mixmat.es link with an external-link icon. Used as
/// `safeAreaInset(edge: .bottom)` content on every top-level screen so the
/// affordance to the companion web service appears in the same place
/// throughout the app. Users were already treating the footer as a
/// bookmark to navigate to mixmat.es; this makes that consistent.
///
/// The `.bar` material background prevents scrollable content underneath
/// (in `List`/`Form`/`ScrollView`) from reading through and visually
/// overlapping the link. Matches the toolbar-accessory pattern Apple uses
/// for tab bars and pinned footers.
struct MixMatesLinkFooter: View {
    var body: some View {
        VStack(spacing: 2) {
            Link(destination: URL(string: "https://mixmat.es")!) {
                HStack(spacing: 4) {
                    Text("mixmat.es")
                    Image(systemName: "arrow.up.right")
                        .imageScale(.small)
                }
                .font(.callout)
            }
            Text("© \(currentYear) MixMat Ltd")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.bar)
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

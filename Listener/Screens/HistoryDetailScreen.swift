//
//  HistoryDetailScreen.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import SwiftUI

// Placeholder shell. The real detail screen with TrackCard, share-to-
// groups, and "Open in MixMates" button lands in a follow-up commit.
// Lives here now so the `NavigationLink` from `HistoryScreen` rows
// compiles.
struct HistoryDetailScreen: View {
    let id: String

    var body: some View {
        VStack(spacing: 12) {
            Text("Detail coming next")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(id)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .navigationTitle("Track Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

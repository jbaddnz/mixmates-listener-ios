//
//  TrackCard.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import SwiftUI

/// Reusable card displaying a recognised or saved track.
///
/// Used by `ListenScreen` (recognition result) and `HistoryDetailScreen`
/// (saved track detail). Mirrors the Android sibling's
/// `ui/components/TrackCard.kt` in shape and behaviour: horizontal
/// thumbnail+text layout in a card with rounded corners, optional
/// "Already in your queue!" banner when the recognition status is
/// duplicate, platform link buttons, and a share affordance.
///
/// Convenience initializers accept `Track` (from `RecognitionResult.track`)
/// or `HistoryDetail` so call sites stay tiny.
struct TrackCard: View {

    let title: String
    let artist: String
    let thumbnail: URL?
    let platforms: Platforms
    let shareURL: URL?
    let isDuplicate: Bool

    init(
        title: String,
        artist: String,
        thumbnail: URL?,
        platforms: Platforms,
        shareURL: URL?,
        isDuplicate: Bool = false
    ) {
        self.title = title
        self.artist = artist
        self.thumbnail = thumbnail
        self.platforms = platforms
        self.shareURL = shareURL
        self.isDuplicate = isDuplicate
    }

    init(track: Track, isDuplicate: Bool = false) {
        self.init(
            title: track.title,
            artist: track.artist,
            thumbnail: track.thumbnail,
            platforms: track.platforms,
            shareURL: track.shareURL,
            isDuplicate: isDuplicate
        )
    }

    init(detail: HistoryDetail) {
        self.init(
            title: detail.title,
            artist: detail.artist,
            thumbnail: detail.thumbnail,
            platforms: detail.platforms,
            shareURL: detail.shareURL,
            isDuplicate: false
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                thumbnailView
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text(artist)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            if isDuplicate {
                Label("Already in your queue", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            platformButtons

            if let shareURL {
                ShareLink(item: shareURL) {
                    Label("Share link", systemImage: "square.and.arrow.up")
                }
                .font(.callout)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            AsyncImage(url: thumbnail) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                placeholder
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            placeholder
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var platformButtons: some View {
        let items = platformButtonItems
        if !items.isEmpty {
            HStack(spacing: 8) {
                ForEach(items, id: \.url) { item in
                    Link(item.label, destination: item.url)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }

    private struct PlatformButtonItem {
        let label: String
        let url: URL
    }

    private var platformButtonItems: [PlatformButtonItem] {
        var items: [PlatformButtonItem] = []
        if let spotify = platforms.spotify {
            items.append(PlatformButtonItem(label: "Spotify", url: spotify))
        }
        if let appleMusic = platforms.appleMusic {
            items.append(PlatformButtonItem(label: "Apple Music", url: appleMusic))
        }
        if let tidal = platforms.tidal {
            items.append(PlatformButtonItem(label: "Tidal", url: tidal))
        }
        return items
    }
}

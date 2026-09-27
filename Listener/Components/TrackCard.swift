//
//  TrackCard.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import SwiftUI
import UIKit

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
    let meta: TrackMeta
    let isDuplicate: Bool

    /// Opens the caller's share sheet. The card deliberately knows nothing
    /// about *what* gets shared: it holds no share URL and no history id, so
    /// there is one sharing surface in the app and the card cannot grow a
    /// second one beside it.
    let onShare: () -> Void

    init(
        title: String,
        artist: String,
        thumbnail: URL?,
        platforms: Platforms,
        meta: TrackMeta = .empty,
        isDuplicate: Bool = false,
        onShare: @escaping () -> Void
    ) {
        self.title = title
        self.artist = artist
        self.thumbnail = thumbnail
        self.platforms = platforms
        self.meta = meta
        self.isDuplicate = isDuplicate
        self.onShare = onShare
    }

    init(track: Track, isDuplicate: Bool = false, onShare: @escaping () -> Void) {
        self.init(
            title: track.title,
            artist: track.artist,
            thumbnail: track.thumbnail,
            platforms: track.platforms,
            meta: track.meta,
            isDuplicate: isDuplicate,
            onShare: onShare
        )
    }

    init(detail: HistoryDetail, onShare: @escaping () -> Void) {
        self.init(
            title: detail.title,
            artist: detail.artist,
            thumbnail: detail.thumbnail,
            platforms: detail.platforms,
            meta: detail.meta,
            isDuplicate: false,
            onShare: onShare
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
                    // Tempo and key, for the DJ reading this at a gig.
                    // Absent on a track caught seconds ago and filled in by
                    // the time it is seen again, so the row simply has no
                    // tag rather than an empty or zeroed one.
                    if let metaLabel = meta.label {
                        Text(metaLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            if isDuplicate {
                Label("Already in your queue", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            platformButtons

            // Sharing is the product's thesis — a song is a message — so
            // Share is the hero action and carries the brand gradient.
            // Everything else on this card stays quieter.
            //
            // The hero opens the app's own sheet, which puts groups above
            // the system share: sharing into a group is the point of the
            // product, and the public link is the fallback rather than the
            // headline.
            Button(action: onShare) {
                shareHero
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        }
    }

    private var shareHero: some View {
        Label("Share", systemImage: "square.and.arrow.up")
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(LinearGradient.mixmatesBrand))
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

    /// Platform pills carry equal visual weight — identical shape, size,
    /// and prominence, each in its own brand identity (Tidal's identity is
    /// monochrome, rendered with label/background colours so it adapts to
    /// light and dark). Never let one platform look preferred.
    @ViewBuilder
    private var platformButtons: some View {
        let items = platformButtonItems
        if !items.isEmpty {
            HStack(spacing: 8) {
                ForEach(items, id: \.url) { item in
                    Link(destination: item.url) {
                        Text(item.label)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(item.foreground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(item.background))
                    }
                }
            }
        }
    }

    private struct PlatformButtonItem {
        let label: String
        let url: URL
        let background: Color
        let foreground: Color
    }

    private static let spotifyGreen = Color(red: 29 / 255, green: 185 / 255, blue: 84 / 255)
    private static let appleMusicRed = Color(red: 250 / 255, green: 36 / 255, blue: 60 / 255)

    private var platformButtonItems: [PlatformButtonItem] {
        var items: [PlatformButtonItem] = []
        if let spotify = platforms.spotify {
            items.append(PlatformButtonItem(
                label: "Spotify", url: spotify,
                background: Self.spotifyGreen, foreground: .white
            ))
        }
        if let appleMusic = platforms.appleMusic {
            items.append(PlatformButtonItem(
                label: "Apple Music", url: appleMusic,
                background: Self.appleMusicRed, foreground: .white
            ))
        }
        if let tidal = platforms.tidal {
            items.append(PlatformButtonItem(
                label: "Tidal", url: tidal,
                background: .primary, foreground: Color(uiColor: .systemBackground)
            ))
        }
        return items
    }
}

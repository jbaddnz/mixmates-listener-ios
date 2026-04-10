//
//  Track.swift
//  Listener
//
//  Created by jamie baddeley on 10/04/2026.
//

import Foundation

// MARK: - Wire

struct TrackDTO: Decodable {
    let title: String
    let artist: String
    let thumbnail: String?
    let shortcode: String?
    let shareUrl: String?
    let platforms: PlatformsDTO?

    enum CodingKeys: String, CodingKey {
        case title
        case artist
        case thumbnail
        case shortcode
        case shareUrl = "share_url"
        case platforms
    }
}

struct PlatformsDTO: Decodable {
    let spotify: String?
    let tidal: String?
    let appleMusic: String?
}

// MARK: - Domain

struct Track: Equatable {
    let title: String
    let artist: String
    let thumbnail: URL?
    let shortcode: String?
    let shareURL: URL?
    let platforms: Platforms

    init(dto: TrackDTO) {
        self.title = dto.title
        self.artist = dto.artist
        self.thumbnail = dto.thumbnail.flatMap(URL.init(string:))
        self.shortcode = dto.shortcode
        self.shareURL = dto.shareUrl.flatMap(URL.init(string:))
        self.platforms = dto.platforms.map(Platforms.init(dto:)) ?? .empty
    }
}

struct Platforms: Equatable {
    let spotify: URL?
    let tidal: URL?
    let appleMusic: URL?

    static let empty = Platforms(spotify: nil, tidal: nil, appleMusic: nil)

    init(spotify: URL?, tidal: URL?, appleMusic: URL?) {
        self.spotify = spotify
        self.tidal = tidal
        self.appleMusic = appleMusic
    }

    init(dto: PlatformsDTO) {
        self.init(
            spotify: dto.spotify.flatMap(URL.init(string:)),
            tidal: dto.tidal.flatMap(URL.init(string:)),
            appleMusic: dto.appleMusic.flatMap(URL.init(string:))
        )
    }
}

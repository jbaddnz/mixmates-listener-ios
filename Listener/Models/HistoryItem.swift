//
//  HistoryItem.swift
//  Listener
//
//  Created by jamie baddeley on 10/04/2026.
//

import Foundation

// MARK: - Wire

struct HistoryListDTO: Decodable {
    let items: [HistoryItemDTO]
    let cursor: String?
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case items
        case cursor
        case hasMore = "has_more"
    }
}

struct HistoryItemDTO: Decodable {
    let id: String
    let title: String
    let artist: String
    let thumbnail: String?
    let shortcode: String?
    let shareUrl: String?
    let platforms: PlatformsDTO?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, artist, thumbnail, shortcode, platforms
        case shareUrl = "share_url"
        case createdAt = "created_at"
    }
}

struct HistoryDetailDTO: Decodable {
    let id: String
    let title: String
    let artist: String
    let thumbnail: String?
    let shortcode: String?
    let shareUrl: String?
    let platforms: PlatformsDTO?
    let createdAt: String
    let sharedTo: [SharedGroupDTO]

    enum CodingKeys: String, CodingKey {
        case id, title, artist, thumbnail, shortcode, platforms
        case shareUrl = "share_url"
        case createdAt = "created_at"
        case sharedTo = "shared_to"
    }
}

struct SharedGroupDTO: Decodable {
    let groupId: String
    let groupName: String

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case groupName = "group_name"
    }
}

struct DeletedDTO: Decodable {
    let deleted: Bool
}

// MARK: - Domain

struct HistoryList: Equatable {
    let items: [HistoryItem]
    let cursor: String?
    let hasMore: Bool

    init(dto: HistoryListDTO) {
        self.items = dto.items.map(HistoryItem.init(dto:))
        self.cursor = dto.cursor
        self.hasMore = dto.hasMore
    }
}

struct HistoryItem: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let thumbnail: URL?
    let shortcode: String?
    let shareURL: URL?
    let platforms: Platforms
    let createdAt: String

    init(dto: HistoryItemDTO) {
        self.id = dto.id
        self.title = dto.title
        self.artist = dto.artist
        self.thumbnail = dto.thumbnail.flatMap(URL.init(string:))
        self.shortcode = dto.shortcode
        self.shareURL = dto.shareUrl.flatMap(URL.init(string:))
        self.platforms = dto.platforms.map(Platforms.init(dto:)) ?? .empty
        self.createdAt = dto.createdAt
    }
}

struct HistoryDetail: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let thumbnail: URL?
    let shortcode: String?
    let shareURL: URL?
    let platforms: Platforms
    let createdAt: String
    let sharedTo: [SharedGroup]

    init(dto: HistoryDetailDTO) {
        self.id = dto.id
        self.title = dto.title
        self.artist = dto.artist
        self.thumbnail = dto.thumbnail.flatMap(URL.init(string:))
        self.shortcode = dto.shortcode
        self.shareURL = dto.shareUrl.flatMap(URL.init(string:))
        self.platforms = dto.platforms.map(Platforms.init(dto:)) ?? .empty
        self.createdAt = dto.createdAt
        self.sharedTo = dto.sharedTo.map(SharedGroup.init(dto:))
    }
}

struct SharedGroup: Equatable {
    let groupId: String
    let groupName: String

    init(dto: SharedGroupDTO) {
        self.groupId = dto.groupId
        self.groupName = dto.groupName
    }
}

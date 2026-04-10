//
//  Recording.swift
//  Listener
//
//  Created by jamie baddeley on 10/04/2026.
//

import Foundation

// MARK: - Wire

struct RecordingListDTO: Decodable {
    let items: [RecordingDTO]
}

struct RecordingDTO: Decodable {
    let recordingId: String
    let createdAt: String?
    let outcome: String?
    let title: String?
    let artist: String?
    let mimeType: String?

    enum CodingKeys: String, CodingKey {
        case recordingId = "recording_id"
        case createdAt = "created_at"
        case outcome, title, artist
        case mimeType = "mime_type"
    }
}

struct DeletedCountDTO: Decodable {
    let deleted: Int
}

// MARK: - Domain

enum RecordingOutcome: Equatable {
    case matched
    case unmatched
    case other(String)

    init(rawValue: String) {
        switch rawValue {
        case "matched": self = .matched
        case "unmatched", "no_match": self = .unmatched
        default: self = .other(rawValue)
        }
    }
}

struct Recording: Identifiable, Equatable {
    let id: String
    let createdAt: String?
    let outcome: RecordingOutcome?
    let title: String?
    let artist: String?
    let mimeType: String?

    init(dto: RecordingDTO) {
        self.id = dto.recordingId
        self.createdAt = dto.createdAt
        self.outcome = dto.outcome.map(RecordingOutcome.init(rawValue:))
        self.title = dto.title
        self.artist = dto.artist
        self.mimeType = dto.mimeType
    }
}

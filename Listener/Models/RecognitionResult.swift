//
//  RecognitionResult.swift
//  Listener
//
//  Created by jamie baddeley on 10/04/2026.
//

import Foundation

// MARK: - Wire

struct RecognizeDTO: Decodable {
    let status: String
    let historyId: String?
    let source: String?
    let track: TrackDTO?

    enum CodingKeys: String, CodingKey {
        case status
        case historyId = "history_id"
        case source
        case track
    }
}

// MARK: - Domain

/// Outcome of `POST /recognize`. The `.other` case keeps the client
/// forward-compatible if the server adds new statuses without a client update.
enum RecognitionStatus: Equatable {
    case saved
    case duplicate
    case noMatch
    case noLinks
    case other(String)

    init(rawValue: String) {
        switch rawValue {
        case "saved": self = .saved
        case "duplicate": self = .duplicate
        case "no_match": self = .noMatch
        case "no_links": self = .noLinks
        default: self = .other(rawValue)
        }
    }
}

struct RecognitionResult: Equatable {
    let status: RecognitionStatus
    let historyId: String?
    let source: String?
    let track: Track?

    init(dto: RecognizeDTO) {
        self.status = RecognitionStatus(rawValue: dto.status)
        self.historyId = dto.historyId
        self.source = dto.source
        self.track = dto.track.map(Track.init(dto:))
    }
}

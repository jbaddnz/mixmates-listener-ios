//
//  ShareRequest.swift
//  Listener
//
//  Created by jamie baddeley on 10/04/2026.
//

import Foundation

// MARK: - Wire

struct ShareRequestDTO: Encodable {
    let groupIds: [String]

    enum CodingKeys: String, CodingKey {
        case groupIds = "group_ids"
    }
}

struct ShareDataDTO: Decodable {
    let results: [ShareResultDTO]
}

struct ShareResultDTO: Decodable {
    let groupId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case status
    }
}

// MARK: - Domain

enum ShareStatus: Equatable {
    case shared
    case duplicate
    case other(String)

    init(rawValue: String) {
        switch rawValue {
        case "shared": self = .shared
        case "duplicate": self = .duplicate
        default: self = .other(rawValue)
        }
    }
}

struct ShareResult: Equatable {
    let groupId: String
    let status: ShareStatus

    init(dto: ShareResultDTO) {
        self.groupId = dto.groupId
        self.status = ShareStatus(rawValue: dto.status)
    }
}

struct ShareOutcome: Equatable {
    let results: [ShareResult]

    init(dto: ShareDataDTO) {
        self.results = dto.results.map(ShareResult.init(dto:))
    }
}

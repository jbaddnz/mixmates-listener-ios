//
//  UserProfile.swift
//  Listener
//
//  Created by jamie baddeley on 10/04/2026.
//

import Foundation

// MARK: - Wire

struct UserDTO: Decodable {
    let user: UserInfoDTO
    let rateLimit: RateLimitDTO?

    enum CodingKeys: String, CodingKey {
        case user
        case rateLimit = "rate_limit"
    }
}

struct UserInfoDTO: Decodable {
    let id: String
    let displayName: String
    let role: String
    let listenEnabled: Bool
    let preferredPlatform: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case role
        case listenEnabled = "listen_enabled"
        case preferredPlatform = "preferred_platform"
    }
}

struct RateLimitDTO: Decodable {
    let limit: Int
    let remaining: Int
    let resetAt: Int

    enum CodingKeys: String, CodingKey {
        case limit, remaining
        case resetAt = "reset_at"
    }
}

// MARK: - Domain

struct UserProfile: Equatable {
    let id: String
    let displayName: String
    let role: String
    let listenEnabled: Bool
    let preferredPlatform: String?
    let rateLimit: RateLimit?

    init(dto: UserDTO) {
        self.id = dto.user.id
        self.displayName = dto.user.displayName
        self.role = dto.user.role
        self.listenEnabled = dto.user.listenEnabled
        self.preferredPlatform = dto.user.preferredPlatform
        self.rateLimit = dto.rateLimit.map(RateLimit.init(dto:))
    }
}

struct RateLimit: Equatable {
    let limit: Int
    let remaining: Int
    let resetAt: Date

    init(dto: RateLimitDTO) {
        self.limit = dto.limit
        self.remaining = dto.remaining
        self.resetAt = Date(timeIntervalSince1970: TimeInterval(dto.resetAt))
    }
}

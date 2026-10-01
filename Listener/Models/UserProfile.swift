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

// MARK: - Domain

struct UserProfile: Equatable {
    let id: String
    let displayName: String
    let role: String
    let listenEnabled: Bool
    let preferredPlatform: String?

    init(dto: UserDTO) {
        self.id = dto.user.id
        self.displayName = dto.user.displayName
        self.role = dto.user.role
        self.listenEnabled = dto.user.listenEnabled
        self.preferredPlatform = dto.user.preferredPlatform
    }

    /// The server's limit on a display name, counted after trimming.
    static let displayNameMaxLength = 100

    /// The name as it would be sent to `updateDisplayName(_:)`, trimmed, or
    /// nil when the server would refuse it as empty or too long. Checked
    /// before sending so the common mistakes never cost a round trip.
    static func validDisplayName(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= displayNameMaxLength else { return nil }
        return trimmed
    }
}

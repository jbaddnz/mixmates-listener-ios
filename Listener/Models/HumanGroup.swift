//
//  HumanGroup.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import Foundation

// MARK: - Wire

/// Both `can_create` and `invite_url` are optional on the wire. A required
/// field would make an older server's response fail to decode, which would
/// break the share picker outright rather than just hide Start a group.
struct HumanGroupListDTO: Decodable {
    let items: [HumanGroupDTO]
    let canCreate: Bool?

    enum CodingKeys: String, CodingKey {
        case items
        case canCreate = "can_create"
    }
}

struct HumanGroupDTO: Decodable {
    let id: String
    let name: String
    let description: String?
    let inviteUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case inviteUrl = "invite_url"
    }
}

// MARK: - Domain

/// A group of humans the signed-in person belongs to (Wellington Batucada,
/// Studio Crew, etc.) — the share targets for tracks identified via the
/// listener.
///
/// Named `HumanGroup` rather than `Group` to avoid shadowing SwiftUI's
/// `Group` view builder, and rather than `UserGroup` because MixMates is
/// built for humans, not users. This is a deliberate, intentional deviation
/// from the Android sibling's `Group` naming.
struct HumanGroup: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String?

    /// The link that admits a friend, for the person to send. Nil on the
    /// demo group, which hides Invite there.
    let inviteURL: URL?

    init(dto: HumanGroupDTO) {
        self.id = dto.id
        self.name = dto.name
        self.description = dto.description
        self.inviteURL = dto.inviteUrl.flatMap(URL.init(string:))
    }

    /// The server's limit on a group name, counted after trimming.
    static let nameMaxLength = 100

    /// The name as it would be sent to `createGroup(name:)`, trimmed, or nil
    /// when the server would refuse it as empty or too long.
    static func validName(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= nameMaxLength else { return nil }
        return trimmed
    }
}

/// The groups response: the groups themselves, and whether this account may
/// start one.
///
/// `canCreate` is the server's decision and only ever read from a fresh
/// response. It is never cached, never assumed when a fetch fails, and a
/// missing field means no.
struct GroupList: Equatable {
    let groups: [HumanGroup]
    let canCreate: Bool

    init(groups: [HumanGroup], canCreate: Bool) {
        self.groups = groups
        self.canCreate = canCreate
    }

    init(dto: HumanGroupListDTO) {
        self.groups = dto.items.map(HumanGroup.init(dto:))
        self.canCreate = dto.canCreate ?? false
    }
}

//
//  HumanGroup.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import Foundation

// MARK: - Wire

struct HumanGroupListDTO: Decodable {
    let items: [HumanGroupDTO]
}

struct HumanGroupDTO: Decodable {
    let id: String
    let name: String
    let description: String?
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

    init(dto: HumanGroupDTO) {
        self.id = dto.id
        self.name = dto.name
        self.description = dto.description
    }
}

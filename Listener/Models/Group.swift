//
//  Group.swift
//  Listener
//
//  Created by jamie baddeley on 10/04/2026.
//

import Foundation

// MARK: - Wire

struct GroupListDTO: Decodable {
    let items: [GroupDTO]
}

struct GroupDTO: Decodable {
    let id: String
    let name: String
    let description: String?
}

// MARK: - Domain

struct Group: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String?

    init(dto: GroupDTO) {
        self.id = dto.id
        self.name = dto.name
        self.description = dto.description
    }
}

//
//  AppleAuth.swift
//  Listener
//
//  Created by jamie baddeley on 25/04/2026.
//

import Foundation

// MARK: - Wire

struct AppleAuthDTO: Decodable {
    let token: String
    let isNewAccount: Bool
    let listenEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case token
        case isNewAccount = "is_new_account"
        case listenEnabled = "listen_enabled"
    }
}

// MARK: - Domain

struct AppleAuthResult: Equatable {
    let token: String
    let isNewAccount: Bool
    let listenEnabled: Bool

    init(dto: AppleAuthDTO) {
        self.token = dto.token
        self.isNewAccount = dto.isNewAccount
        self.listenEnabled = dto.listenEnabled
    }
}

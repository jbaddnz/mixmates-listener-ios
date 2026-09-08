//
//  Auth.swift
//  Listener
//
//  Created by jamie baddeley on 25/04/2026.
//

import Foundation

// MARK: - Wire

/// Response body shared by `POST /auth/apple` and `POST /auth/google`.
/// Both endpoints mint the same session shape, so one DTO serves both.
struct AuthResultDTO: Decodable {
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

struct AuthResult: Equatable {
    let token: String
    let isNewAccount: Bool
    let listenEnabled: Bool

    init(dto: AuthResultDTO) {
        self.token = dto.token
        self.isNewAccount = dto.isNewAccount
        self.listenEnabled = dto.listenEnabled
    }
}

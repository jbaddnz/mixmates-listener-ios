//
//  PushRegistration.swift
//  Listener
//
//  Created by jamie baddeley on 21/04/2026.
//

import Foundation

// MARK: - Wire

struct PushRegisteredDTO: Decodable {
    let registered: Bool
}

struct PushDeregisteredDTO: Decodable {
    let deregistered: Bool
}

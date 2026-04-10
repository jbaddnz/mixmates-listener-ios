//
//  Health.swift
//  Listener
//
//  Created by jamie baddeley on 10/04/2026.
//

import Foundation

/// `GET /health` — unauthenticated liveness check.
struct HealthDTO: Decodable, Equatable {
    let status: String
    let version: String
}

//
//  APIEnvelope.swift
//  Listener
//
//  Created by jamie baddeley on 10/04/2026.
//

import Foundation

/// Generic envelope wrapping every successful response from the Listener API.
///
/// All endpoints return `{ "data": <T>, "meta": { ... } }`.
struct APIResponse<T: Decodable>: Decodable {
    let data: T
    let meta: APIMeta?
}

/// Envelope returned on error: `{ "error": { ... }, "meta": { ... } }`.
struct APIErrorEnvelope: Decodable {
    let error: APIErrorPayload
    let meta: APIMeta?
}

/// On-wire error payload. `code` matches the documented error codes
/// (e.g. `auth_required`, `rate_limit_user`, `audio_too_large`, ...).
struct APIErrorPayload: Decodable, Equatable {
    let code: String
    let message: String
}

/// Metadata attached to every response.
struct APIMeta: Decodable {
    let requestId: String?
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case timestamp
    }
}

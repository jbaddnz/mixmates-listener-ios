//
//  APIError.swift
//  Listener
//
//  Created by jamie baddeley on 10/04/2026.
//

import Foundation

/// Errors thrown by `ListenerAPI`. The actor catches network/decoding/HTTP
/// failures internally and surfaces them as cases of this enum so callers
/// only ever need to switch on `APIError`.
enum APIError: Error, Equatable {
    /// Network-level failure (no response, timeout, DNS, offline, ...).
    case network(URLError)

    /// JSON decode failure for a successful response.
    case decoding(String)

    /// 401 Unauthorized — token is missing, invalid, or revoked.
    /// The actor has already invoked its `onUnauthorized` callback;
    /// the caller should navigate back to the token entry screen.
    case unauthorized(payload: APIErrorPayload?)

    /// 429 Too Many Requests, parsed from `Retry-After` and
    /// `X-RateLimit-Remaining` response headers.
    case rateLimited(retryAfter: Int, remaining: Int?)

    /// 502 Bad Gateway — recognition service (AudD) is currently down.
    case recognitionUnavailable

    /// 403 with error code `group_locked` — a target group is in mastering
    /// mode and the caller is not the creator / a co-creator. The group's
    /// curator has frozen the tracklist; reactions and notes remain open
    /// via the web app, but new tracks can only be added by the curator
    /// team. Surfaced by `resolve` and `shareHistory`.
    case groupLocked(payload: APIErrorPayload?)

    /// 403 with error code `name_required` — the account has no display
    /// name of its own yet, so it cannot put anything where friends will
    /// see it. Refuses the whole request; nothing was applied. Resolved in
    /// place by `updateDisplayName(_:)` and one retry. Surfaced by
    /// `shareHistory`.
    case nameRequired(payload: APIErrorPayload?)

    /// 403 with error code `not_found` — the caller is not a member of a
    /// target group, usually because they left it. The status and code look
    /// mismatched but that pairing is the server's contract. Surfaced by
    /// `shareHistory`.
    case notGroupMember(payload: APIErrorPayload?)

    /// 403 with error code `auth_listen_disabled` — an admin has switched
    /// listening off for this account. Comes from the server's shared auth
    /// step, so any authenticated route can return it, and it is permanent:
    /// no retry will succeed.
    case listenDisabled(payload: APIErrorPayload?)

    /// 400 with error code `private_relay_name` — the display name sent to
    /// `updateDisplayName(_:)` is an Apple private-relay address. Kept apart
    /// from a plain `invalid_field` so the app can say exactly what was wrong.
    case privateRelayName(payload: APIErrorPayload?)

    /// Any other non-2xx status with the parsed error envelope, if present.
    case http(status: Int, payload: APIErrorPayload?)

    /// Response was missing, malformed, or otherwise not what we expected.
    case unexpected(String)

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.network(let l), .network(let r)):
            return l.code == r.code
        case (.decoding(let l), .decoding(let r)):
            return l == r
        case (.unauthorized(let l), .unauthorized(let r)):
            return l == r
        case (.rateLimited(let lr, let lrem), .rateLimited(let rr, let rrem)):
            return lr == rr && lrem == rrem
        case (.recognitionUnavailable, .recognitionUnavailable):
            return true
        case (.groupLocked(let l), .groupLocked(let r)),
             (.nameRequired(let l), .nameRequired(let r)),
             (.notGroupMember(let l), .notGroupMember(let r)),
             (.listenDisabled(let l), .listenDisabled(let r)),
             (.privateRelayName(let l), .privateRelayName(let r)):
            return l == r
        case (.http(let ls, let lp), .http(let rs, let rp)):
            return ls == rs && lp == rp
        case (.unexpected(let l), .unexpected(let r)):
            return l == r
        default:
            return false
        }
    }
}

//
//  Fixtures.swift
//  ListenerTests
//
//  Created by jamie baddeley on 10/04/2026.
//

import Foundation

/// JSON response fixtures derived from the Listener API spec examples.
/// Inlined as Swift string literals so the test bundle does not need a
/// separate resources phase — fast iteration, no Bundle.module dance.
enum Fixtures {

    static let health = #"""
    { "data": { "status": "ok", "version": "1" } }
    """#

    static let authMe = #"""
    {
      "data": {
        "user": {
          "id": "u_abc123",
          "display_name": "Jamie",
          "role": "paid",
          "listen_enabled": true,
          "preferred_platform": "tidal"
        },
        "rate_limit": {
          "limit": 20,
          "remaining": 17,
          "reset_at": 1709654400
        }
      }
    }
    """#

    static let recognizeSaved = #"""
    {
      "data": {
        "status": "saved",
        "source": "recognition",
        "track": {
          "title": "Midnight City",
          "artist": "M83",
          "thumbnail": "https://img.example.com/m83.jpg",
          "shortcode": "aBcDeF12",
          "share_url": "https://mixmat.es/aBcDeF12",
          "platforms": {
            "spotify": "https://open.spotify.com/track/abc",
            "tidal": "https://tidal.com/browse/track/abc",
            "appleMusic": "https://music.apple.com/us/album/abc"
          }
        }
      }
    }
    """#

    static let recognizeNoMatch = #"""
    {
      "data": {
        "status": "no_match",
        "source": null,
        "track": null
      }
    }
    """#

    static let history = #"""
    {
      "data": {
        "items": [
          {
            "id": "h_1",
            "title": "Midnight City",
            "artist": "M83",
            "thumbnail": "https://img.example.com/m83.jpg",
            "shortcode": "aBcDeF12",
            "share_url": "https://mixmat.es/aBcDeF12",
            "platforms": {
              "spotify": "https://open.spotify.com/track/abc"
            },
            "created_at": "2026-04-10T10:00:00Z"
          },
          {
            "id": "h_2",
            "title": "Strobe",
            "artist": "deadmau5",
            "thumbnail": null,
            "shortcode": "xYz12345",
            "share_url": "https://mixmat.es/xYz12345",
            "platforms": {},
            "created_at": "2026-04-09T22:30:00Z"
          }
        ],
        "cursor": "next_cursor_token",
        "has_more": true
      }
    }
    """#

    /// First page of history with `cursor: null` and `has_more: false`.
    /// Used by tests that exercise the empty / final-page branch of the
    /// pagination state machine.
    static let historyEmpty = #"""
    {
      "data": {
        "items": [],
        "cursor": null,
        "has_more": false
      }
    }
    """#

    /// Second page of history (cursor exhausted). Different items than the
    /// first page so pagination tests can verify items are appended, not
    /// replaced.
    static let historyPage2 = #"""
    {
      "data": {
        "items": [
          {
            "id": "h_3",
            "title": "Resonance",
            "artist": "HOME",
            "thumbnail": "https://img.example.com/home.jpg",
            "shortcode": "rEsOn8nC",
            "share_url": "https://mixmat.es/rEsOn8nC",
            "platforms": {
              "spotify": "https://open.spotify.com/track/home"
            },
            "created_at": "2026-04-08T15:00:00Z"
          }
        ],
        "cursor": null,
        "has_more": false
      }
    }
    """#

    static let historyDetail = #"""
    {
      "data": {
        "id": "h_1",
        "title": "Midnight City",
        "artist": "M83",
        "thumbnail": "https://img.example.com/m83.jpg",
        "shortcode": "aBcDeF12",
        "share_url": "https://mixmat.es/aBcDeF12",
        "platforms": {
          "spotify": "https://open.spotify.com/track/abc",
          "tidal": "https://tidal.com/browse/track/abc",
          "appleMusic": "https://music.apple.com/us/album/abc"
        },
        "created_at": "2026-04-10T10:00:00Z",
        "shared_to": [
          { "group_id": "g1", "group_name": "Wellington Batucada" }
        ]
      }
    }
    """#

    static let historyDelete = #"""
    { "data": { "deleted": true } }
    """#

    static let groups = #"""
    {
      "data": {
        "items": [
          { "id": "g1", "name": "Wellington Batucada", "description": "Fortnightly drum sessions" },
          { "id": "g2", "name": "Studio Crew", "description": null }
        ]
      }
    }
    """#

    static let share = #"""
    {
      "data": {
        "results": [
          { "group_id": "g1", "status": "shared" },
          { "group_id": "g2", "status": "duplicate" }
        ]
      }
    }
    """#

    static let recordings = #"""
    {
      "data": {
        "items": [
          {
            "recording_id": "r_1",
            "created_at": "2026-04-10T10:00:00Z",
            "outcome": "matched",
            "title": "Midnight City",
            "artist": "M83",
            "mime_type": "audio/mp4"
          }
        ]
      }
    }
    """#

    static let recordingsDelete = #"""
    { "data": { "deleted": 3 } }
    """#

    static let errorEnvelope = #"""
    {
      "error": {
        "code": "auth_required",
        "message": "Authentication required"
      },
      "meta": {
        "request_id": "req_abc",
        "timestamp": "2026-04-10T10:00:00Z"
      }
    }
    """#

    /// `GET /auth/me` response for an account where Listen is not enabled.
    /// Used by `TokenEntryViewModelTests` to verify the listen-disabled
    /// branch of the verification flow.
    static let authMeListenDisabled = #"""
    {
      "data": {
        "user": {
          "id": "u_xyz",
          "display_name": "Test",
          "role": "free",
          "listen_enabled": false,
          "preferred_platform": null
        }
      }
    }
    """#
}

# iOS Listener App — Implementation Spec

Standalone iOS app — replaces the iOS Shortcut with a native app. Separate project, separate repo (`jbaddnz/mixmates-listener-ios`). Must achieve feature parity with the Android Listener app (`jbaddnz/mixmates-listener-android`).

## Reference material

- **API spec:** [Listener API v1 OpenAPI](https://github.com/jbaddnz/mixmates-listener-api/blob/main/listener-v1-openapi.yaml)
- **Developer guide:** [Building a Listener App](https://github.com/jbaddnz/mixmates-listener-api/blob/main/DEVELOPER_GUIDE.md)
- **Interactive docs:** [https://jbaddnz.github.io/mixmates-listener-api/](https://jbaddnz.github.io/mixmates-listener-api/)
- **Android reference app:** [https://github.com/jbaddnz/mixmates-listener-android](https://github.com/jbaddnz/mixmates-listener-android)
- **Base URL:** `https://mixmat.es/api/v1/listener`

The Android app is the functional spec. The iOS app should match its behaviour screen-for-screen.

## Why

The iOS Shortcut works but has UX friction: brief Shortcuts banner on launch, no custom icon inside Shortcuts app, no auto-updates, manual setup with Import Questions. A native app gives a clean launch, proper icon, push-based updates, and the same native mic access the Shortcut already benefits from. Platform parity with the Android app is the primary driver.

## Tech stack

| Concern | Choice | Notes |
|---|---|---|
| Language | Swift | |
| Min deployment | iOS 16 | ~95% of active devices |
| UI | SwiftUI | |
| Architecture | MVVM | ObservableObject + @Published |
| Networking | URLSession + Codable | No third-party HTTP library needed |
| Local storage | SwiftData | Offline recognition queue |
| Background sync | BGTaskScheduler | Sync queued recognitions when online |
| Image loading | AsyncImage | Built-in SwiftUI |
| Token storage | Keychain Services | Via Security framework |
| DI | Environment + init injection | No framework needed |
| Testing | XCTest | API client + UI tests |
| CI | GitHub Actions | xcodebuild |

## API endpoints used

All require `Authorization: Bearer {listen_key}` except `/health`.

### `GET /health`
No auth. Returns `{ "data": { "status": "ok", "version": "1" } }`.

### `GET /auth/me`
Verify token, get user info and rate limit status.
```json
{
  "data": {
    "user": { "id": "...", "display_name": "...", "role": "paid", "listen_enabled": true, "preferred_platform": "tidal" },
    "rate_limit": { "limit": 20, "remaining": 17, "reset_at": 1709654400 }
  }
}
```

### `POST /recognize`
`multipart/form-data` with `audio` field (max 5MB).
```json
{
  "data": {
    "status": "saved",
    "source": "recognition",
    "track": {
      "title": "Midnight City", "artist": "M83",
      "thumbnail": "https://...",
      "shortcode": "aBcDeF12",
      "share_url": "https://mixmat.es/aBcDeF12",
      "platforms": { "spotify": "https://...", "tidal": "https://...", "appleMusic": "https://..." }
    }
  }
}
```
Status values: `saved`, `duplicate`, `no_match`, `no_links`. `track` is null when `no_match`.

### `GET /history`
Paginated listen queue. Params: `cursor` (string), `limit` (1-50, default 20).
```json
{
  "data": { "items": [{ "id": "...", "title": "...", "artist": "...", "thumbnail": "...", "shortcode": "...", "share_url": "...", "platforms": {}, "created_at": "..." }], "cursor": "...", "has_more": true }
}
```

### `GET /history/:id`
Single item with share status.
```json
{
  "data": { "id": "...", "title": "...", "artist": "...", "platforms": {}, "shared_to": [{ "group_id": "g1", "group_name": "..." }], ... }
}
```

### `POST /history/:id/share`
Body: `{ "group_ids": ["g1", "g2"] }` (max 20).
```json
{ "data": { "results": [{ "group_id": "g1", "status": "shared" }, { "group_id": "g2", "status": "duplicate" }] } }
```

### `DELETE /history/:id`
Remove from listen queue. Returns `{ "data": { "deleted": true } }`.

### `GET /groups`
Groups for share target selection (excludes Listen group).
```json
{ "data": { "items": [{ "id": "g1", "name": "Wellington Batucada", "description": "..." }] } }
```

### `GET /recordings`
List saved recordings (max 5, 30-day TTL).
```json
{ "data": { "items": [{ "recording_id": "...", "created_at": "...", "outcome": "matched", "title": "...", "artist": "...", "mime_type": "audio/webm" }] } }
```

### `DELETE /recordings`
Delete all recordings.

### Rate limits
Every response includes `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`. Recognition: 20/hr (paid), 100/hr (VIP). 429 responses include `Retry-After`.

### Error responses
```json
{ "error": { "code": "auth_required", "message": "Authentication required" }, "meta": { ... } }
```
Codes: `auth_required` (401), `auth_invalid_token` (401), `auth_token_revoked` (401), `auth_insufficient_role` (403), `auth_listen_disabled` (403), `rate_limit_user` (429), `rate_limit_global` (429), `missing_audio` (400), `audio_too_large` (400), `not_found` (404), `recognition_unavailable` (502).

## Navigation flow

```
TokenEntryScreen → ListenScreen ↔ HistoryScreen → HistoryDetailScreen
                       ↕
                  SettingsScreen
```

- **App launch:** if token in Keychain → ListenScreen. If no token → TokenEntryScreen
- **ListenScreen:** bottom nav or toolbar links to History and Settings
- **HistoryScreen:** list of items, tap → HistoryDetailScreen
- **HistoryDetailScreen:** track info, platform links, group share toggles
- **SettingsScreen:** show user info, sign out (clear Keychain, return to TokenEntryScreen)

## Screen specifications

### TokenEntryScreen
- Text field for Listen key (paste from clipboard)
- "Verify" button → calls `GET /auth/me`
- Success: store token in Keychain, navigate to ListenScreen
- Failure: show error ("Invalid key", "Listen not enabled", "Network error")
- Link to `https://mixmat.es/install` for setup instructions

### ListenScreen
- Large circular record button (centre)
- States: **idle** → **recording** (11s countdown with progress ring) → **recognising** (spinner) → **result** or **error**
- Result: track artwork, title, artist, platform buttons (Spotify/Tidal/Apple Music — only show platforms that exist), share link button
- Platform buttons open the URL (Universal Links will open the platform app if installed)
- Share button → UIActivityViewController with share URL only (not title/text — matches web app behaviour)
- "No match" state: show message, return to idle
- Error states: network error, rate limited (show remaining time), recognition service down
- Toolbar: History button (left/right), Settings button

### HistoryScreen
- Paginated list from `GET /history`
- Each row: thumbnail (48px), artist, title, timestamp
- Pull-to-refresh
- Load more on scroll (cursor-based pagination)
- Tap → HistoryDetailScreen
- Back button → ListenScreen
- Empty state: "No tracks yet"

### HistoryDetailScreen
- Track artwork (large), title, artist
- Platform buttons (Spotify/Tidal/Apple Music)
- Share button → UIActivityViewController
- **Group sharing section:** list of groups from `GET /groups`, toggle for each. Already-shared groups shown as selected/disabled. Toggle calls `POST /history/:id/share`
- Delete button → `DELETE /history/:id`, pop back to HistoryScreen
- Back button → HistoryScreen

### SettingsScreen
- Show display name, role from cached `/auth/me` response
- Rate limit info (remaining / limit, reset time)
- "Sign out" button → clear Keychain, navigate to TokenEntryScreen
- App version at bottom
- Back button → ListenScreen

## Offline queue

When recognition fails due to network:

1. Save the audio file + metadata to SwiftData (`PendingRecognition` entity: id, audioData, mimeType, createdAt)
2. Show "Saved — will sync when online" feedback
3. Register BGTaskScheduler task
4. On connectivity: process queue sequentially, POST each recording to `/recognize`
5. On success: remove from local queue, show result via notification
6. On failure (non-network): remove from queue (don't retry permanently)
7. Max 5 pending items (same as server recording limit)

## Audio recording

- **Duration:** 11 seconds
- **Format:** AAC/m4a via AVAudioRecorder
- **Sample rate:** 44.1kHz
- **Quality:** AVAudioQuality.medium (~64-128kbps)
- **Permission:** request on first record attempt, `NSMicrophoneUsageDescription` in Info.plist: "MixMates records a short audio clip to identify the song playing around you."
- **File size:** typically 150-200KB for 11s AAC

```swift
let settings: [String: Any] = [
    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
    AVSampleRateKey: 44100.0,
    AVNumberOfChannelsKey: 1,
    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
]
```

## Design

- Dark theme: background #0a0a0a, text #ccc/#fff, accent #1db954 (green), secondary #00d4ff (cyan)
- MixMates product mark as app icon (mms-square.svg source, rendered to required sizes)
- Record button: large circle, green gradient border, pulse animation while recording
- Platform buttons: pill-shaped, brand colours (Spotify #1db954, Tidal #00d4ff, Apple #fc3c44)
- SF Symbols: `mic.fill` (record), `clock` (history), `gear` (settings), `square.and.arrow.up` (share)
- States: idle (green button), recording (countdown ring animation), recognising (spinner), result (track card)
- Match the Android app's layout and flow as closely as iOS conventions allow

## Project structure

```
mixmates-listener-ios/
  Listener/
    ListenerApp.swift               # App entry point
    Navigation/
      ContentView.swift             # Navigation container
    Screens/
      TokenEntryScreen.swift
      ListenScreen.swift
      HistoryScreen.swift
      HistoryDetailScreen.swift
      SettingsScreen.swift
    Components/
      TrackCard.swift               # Reusable track display
      PlatformButton.swift          # Platform-coloured pill button
      RecordButton.swift            # Animated record button
    Services/
      ListenerAPI.swift             # URLSession API client
      AudioRecorder.swift           # AVAudioRecorder wrapper
      KeychainManager.swift         # Keychain read/write
    Models/
      Track.swift                   # Codable API models
      Group.swift
      Recording.swift
      PendingRecognition.swift      # SwiftData entity
    Theme/
      Colors.swift                  # MixMates brand colours
      Typography.swift
    Assets.xcassets/                 # App icon, colours
    Info.plist                       # Privacy descriptions
  ListenerTests/
    ListenerAPITests.swift
    AudioRecorderTests.swift
  .github/
    workflows/ci.yml                # Build + lint
  README.md
  LICENSE                           # MIT
  docs/
    listener-v1-openapi.yaml        # Bundled API spec
```

## Distribution

- **App Store** — Apple Developer Program ($99/yr, already enrolled as MixMat Ltd)
- **TestFlight** — beta testing before public release
- **Bundle ID:** `es.mixmat.listener`
- **No sideloading** — App Store is the only viable public channel

## Privacy

- Mic accessed only during active recording (user-initiated, never background)
- Audio sent to MixMates server only, processed by AudD for recognition
- Not stored server-side unless user opts in via MixMates web settings
- No analytics, no tracking, no third-party SDKs
- App Store privacy labels: microphone (required), internet (required), no data collection
- App Tracking Transparency not needed (no tracking)

## Migration from Shortcut

- The iOS Shortcut continues to work — no forced migration
- `/install` page updated to recommend the app, with Shortcut as fallback
- Listen key is the same — users enter their existing key
- Shortcut can be deprecated once app is stable and distributed

## Licence

MIT — same as Android. Both apps are open source reference implementations of the Listener API.

## App Store Distribution

### Jamie

- [ ] Apple Developer account confirmed under MixMat Ltd (already active, upgraded Feb 27 2026)
- [ ] App Store Connect — create app listing for `es.mixmat.listener`
- [ ] Screenshots — capture 4-6 from simulator or device: listen screen, recording in progress, recognition result, history, track detail with group sharing
- [ ] App preview video (optional) — 15-30s screen recording showing record → identify → result
- [ ] Age rating questionnaire — fill out in App Store Connect
- [ ] Submit for App Review
- [ ] Link from MixMates install page once live

### Implementation

- [ ] App icon — render MML brand mark (mml-square.svg) to all required sizes (1024x1024 App Store, plus @2x/@3x device sizes)
- [ ] Signing — automatic via Xcode, managed by Apple Developer account
- [ ] Build archive and upload to App Store Connect via Xcode
- [ ] TestFlight — internal testing first, then public beta
- [ ] Write store listing copy — title, subtitle (30 chars), description, keywords, promotional text
- [ ] App privacy details (App Store privacy labels)
- [ ] Update README with App Store badge/link after launch

### Privacy labels

| Data type | Collected | Linked to identity | Tracking |
|---|---|---|---|
| Audio | Yes (sent for recognition) | No | No |
| Identifiers (token) | Yes (stored locally) | No | No |

No analytics, no advertising, no third-party SDKs. App Tracking Transparency not required.

### Content rating guidance

- No violence, sexual content, profanity, or controlled substances
- No user-generated content visible to others directly in this app
- No location data collected
- Microphone access: yes, for audio recognition only, user-initiated
- Expected rating: 4+ (equivalent to Everyone)

### Store listing direction

Match the MixMates voice — personal, direct, grounded. Same tone as the Android Play Store listing. "Hear something, know it, share it with the people who matter."

### Privacy policy

Already hosted at https://mixmat.es/privacy — link in App Store Connect. Covers audio recordings, the Listener, token storage, and third-party data sharing.

## Phase 2 — Platform-specific enhancements (after MVP)

| Feature | Description |
|---|---|
| Lock Screen widget | WidgetKit, one-tap record from lock screen (iOS 16+) |
| Home Screen widget | WidgetKit, record button on home screen |
| Live Activity | Dynamic Island + Lock Screen recording progress and result |
| Haptic feedback | UIFeedbackGenerator on recording start/stop/result |
| Recordings screen | Full UI for `GET /recordings` with playback via `GET /recordings/:id` |
| Siri integration | App Intents — "Hey Siri, listen" triggers recording |
| CI | GitHub Actions — build + lint + test on push |

## Phase 3

- Apple Watch app (record from wrist, WatchKit + WCSession)
- App Clip (lightweight install-free version, 10MB limit)
- Share extension (receive audio shared from other apps for recognition)

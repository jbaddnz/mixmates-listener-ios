# MixMates Listener for iOS

[![CI](https://github.com/jbaddnz/mixmates-listener-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/jbaddnz/mixmates-listener-ios/actions/workflows/ci.yml)

An open-source reference implementation of a music recognition app for iOS, built on the [MixMates Listener API](https://github.com/jbaddnz/mixmates-listener-api).

Record a short clip of what's playing and get one-tap links to the track on Spotify, Tidal, and Apple Music. Share a link from any music app and get cross-platform links back. A complete iOS app built entirely with native Apple frameworks — no third-party dependencies.

This is a working app, but it's also a learning resource. The architecture is intentionally straightforward, the code is MIT-licensed, and every pattern is documented. Fork it, study it, build on it.

## What it does

- **Audio recognition** — 11-second recording, automatic identification via the MixMates API
- **Cross-platform links** — Spotify, Tidal, and Apple Music links for every match
- **Share Extension** — share a link from any music app and get cross-platform links back, with group sharing
- **Listen history** — browse your recognition history with swipe-to-delete
- **Permission-aware UI** — clear handling of mic permission states with a path to Settings

## Make it your own

This reference implementation covers the core flows — record, recognise, and browse your listen queue. There's plenty of room to build on top of it.

**System integrations**

- Add a Lock Screen or Home Screen widget for one-tap recognition
- Build a Live Activity so recognition progress shows in the Dynamic Island
- Wire up a Siri App Intent — "Hey Siri, identify this song"
- Add an Apple Watch companion to record from your wrist

**Offline and background**

- Queue failed recognitions for retry when connectivity returns (SwiftData + BGTaskScheduler)
- Background audio recognition — start listening from a notification or widget without opening the app
- iCloud sync of listen history across devices

**UI and experience**

- Design your own UI and branding — the [wordmark package](assets/mml-wordmark/) is a starting point
- Audio waveform visualisation during the recording countdown
- Theme picker with light, dark, and system-follows modes
- History search and filtering by date, artist, or platform availability

Or take it in a completely different direction.

## Getting started

### Requirements

- iOS 16.0 or higher
- [Xcode](https://developer.apple.com/xcode/) 26 or higher
- A [MixMates](https://mixmat.es) account with Listen enabled
- A Listen Key (generated in MixMates Settings > Listening)

A free Apple ID is enough to build and run on a physical device. An Apple Developer Program subscription is only needed for App Store distribution.

### Build and run

1. Clone the repository:
   ```
   git clone https://github.com/jbaddnz/mixmates-listener-ios.git
   ```

2. Open `Listener.xcodeproj` in Xcode

3. Pick an iOS Simulator or a connected device and hit **Product > Run** (⌘R)

### Simulator tips

- The iOS Simulator does not pass through your Mac's microphone, so audio recognition itself cannot be tested in a simulator. Run on a physical device for full end-to-end testing.
- Everything else — networking, history, navigation, settings — works fine on the simulator and is enough for developing every screen except the recording flow.

## Architecture

- **Language**: Swift
- **UI**: SwiftUI
- **Architecture**: MVVM with `ObservableObject` and `@Published`
- **Networking**: `URLSession` + `Codable`, single `actor` API client
- **Local storage**: Keychain Services (shared between app and Share Extension)
- **Image loading**: `AsyncImage`
- **Dependency injection**: SwiftUI `Environment` + init injection
- **Testing**: Swift Testing (`@Suite`, `@Test`, `#expect`)
- **No third-party dependencies** — everything uses native Apple frameworks

## API

This app integrates with the [MixMates Listener API v1](https://github.com/jbaddnz/mixmates-listener-api). The API handles audio recognition, listen queue management, group sharing, and cross-platform link resolution.

## On openness

This is an open-source client for a commercial API. The code is MIT-licensed and entirely yours to read, fork, and modify. The service behind the API is not — it runs on infrastructure that costs money to operate because we're serious about providing a good base for musical expression.

What we can do is make everything around it open: the client code, the API specification, the documentation. You can see exactly what data leaves your device (an audio clip and a bearer token), exactly where it goes (mixmat.es), and exactly what comes back. There are no third-party SDKs in this app — no analytics, no tracking, no telemetry of any kind.

We think that's an honest trade-off, and we'd rather be upfront about it than pretend it isn't there.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports, feature ideas, and pull requests are all welcome.

## License

[MIT](LICENSE) — use it however you like.

_Apple and Apple Music are trademarks of Apple Inc., registered in the U.S. and other countries._

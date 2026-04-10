# Contributing

Thanks for your interest in contributing to MixMates Listener for iOS.

## Getting started

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes
4. Open a pull request

## Development setup

See the [README](README.md) for build instructions. You'll need Xcode 26 or higher and a Mac running a recent macOS.

## Guidelines

- **Keep changes focused** — one feature or fix per pull request
- **Follow existing patterns** — the project uses MVVM with SwiftUI, an actor-based API client over `URLSession`, `Codable` for JSON, and the Keychain for token storage
- **No third-party dependencies** — everything uses native Apple frameworks. Open an issue first if you have a strong case for adding one
- **Test on a physical device** for anything touching audio recording — the iOS Simulator does not pass through your Mac's microphone, so the recognition flow can only be exercised end-to-end on real hardware

## Reporting bugs

Open an issue with:
- What you expected to happen
- What actually happened
- Steps to reproduce
- Device model and iOS version

## Feature requests

Open an issue describing the feature and why it would be useful.

## Code style

- Swift with standard conventions
- 4-space indentation
- Type names are `PascalCase`; properties, methods, and cases are `camelCase`
- Tests use [Swift Testing](https://developer.apple.com/documentation/testing) (`@Test`, `#expect`), not XCTest

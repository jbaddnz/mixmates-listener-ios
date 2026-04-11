//
//  ListenScreenViewModelTests.swift
//  ListenerTests
//
//  Created by jamie baddeley on 11/04/2026.
//

import Testing
import Foundation
@testable import Listener

/// `@MainActor` because the system under test (`ListenScreenViewModel`) is
/// `@MainActor`. Canned `(Data, HTTPURLResponse)` tuples come from the
/// shared `StubResponses` namespace in `StubResponses.swift` — see the
/// doc comment there for why they live at file scope rather than as
/// instance helpers.
@Suite("ListenScreenViewModel")
@MainActor
struct ListenScreenViewModelTests {

    // MARK: - Success path

    @Test func successfulRecognitionTransitionsToResult() async throws {
        let viewModel = ListenScreenViewModel(
            audioRecorder: StubAudioRecorder(),
            client: StubHTTPClient(handler: { _ in
                StubResponses.ok(Fixtures.recognizeSaved)
            })
        )

        await viewModel.record(token: "test-token", onUnauthorized: {})

        guard case .result(let result) = viewModel.state else {
            Issue.record("Expected .result state, got \(viewModel.state)")
            return
        }
        #expect(result.status == .saved)
        #expect(result.track?.title == "Midnight City")
    }

    @Test func noMatchTransitionsToResultWithNullTrack() async throws {
        let viewModel = ListenScreenViewModel(
            audioRecorder: StubAudioRecorder(),
            client: StubHTTPClient(handler: { _ in
                StubResponses.ok(Fixtures.recognizeNoMatch)
            })
        )

        await viewModel.record(token: "test-token", onUnauthorized: {})

        guard case .result(let result) = viewModel.state else {
            Issue.record("Expected .result state")
            return
        }
        #expect(result.status == .noMatch)
        #expect(result.track == nil)
    }

    // MARK: - Recording errors

    @Test func recordingFailureTransitionsToErrorWithoutCallingAPI() async throws {
        let viewModel = ListenScreenViewModel(
            audioRecorder: FailingAudioRecorder(error: .recordingFailed),
            client: StubHTTPClient(handler: { _ in
                Issue.record("API should not be called when recording fails")
                throw URLError(.unknown)
            })
        )

        await viewModel.record(token: "test-token", onUnauthorized: {})

        guard case .error(let message) = viewModel.state else {
            Issue.record("Expected .error state")
            return
        }
        #expect(message.contains("Couldn't capture audio"))
    }

    @Test func permissionDeniedFromRecordUpdatesPermissionStatusAndReturnsToIdle() async throws {
        let viewModel = ListenScreenViewModel(
            audioRecorder: FailingAudioRecorder(error: .permissionDenied),
            client: StubHTTPClient(handler: { _ in throw URLError(.unknown) })
        )

        await viewModel.record(token: "test-token", onUnauthorized: {})

        // Permission denial doesn't go to .error — it updates
        // permissionStatus and stays in .idle so the view re-renders to
        // the dedicated permission-denied prompt with an "Open Settings"
        // button (much better UX than a generic error message).
        #expect(viewModel.permissionStatus == .denied)
        #expect(viewModel.state == .idle)
    }

    // MARK: - Network errors

    @Test func networkFailureTransitionsToError() async throws {
        let viewModel = ListenScreenViewModel(
            audioRecorder: StubAudioRecorder(),
            client: StubHTTPClient(handler: { _ in
                throw URLError(.notConnectedToInternet)
            })
        )

        await viewModel.record(token: "test-token", onUnauthorized: {})

        guard case .error(let message) = viewModel.state else {
            Issue.record("Expected .error state")
            return
        }
        #expect(message.contains("reach MixMates"))
    }

    @Test func rateLimitedShowsTryLaterMessage() async throws {
        let viewModel = ListenScreenViewModel(
            audioRecorder: StubAudioRecorder(),
            client: StubHTTPClient(handler: { _ in
                StubResponses.http(429)
            })
        )

        await viewModel.record(token: "test-token", onUnauthorized: {})

        guard case .error(let message) = viewModel.state else {
            Issue.record("Expected .error state")
            return
        }
        #expect(message.contains("Wait a moment"))
    }

    @Test func recognitionUnavailableShowsServiceMessage() async throws {
        let viewModel = ListenScreenViewModel(
            audioRecorder: StubAudioRecorder(),
            client: StubHTTPClient(handler: { _ in
                StubResponses.http(502)
            })
        )

        await viewModel.record(token: "test-token", onUnauthorized: {})

        guard case .error(let message) = viewModel.state else {
            Issue.record("Expected .error state")
            return
        }
        #expect(message.contains("temporarily unavailable"))
    }

    // MARK: - Unauthorized

    @Test func unauthorizedTriggersCallbackAndResetsToIdle() async throws {
        let signal = UnauthorizedSignal()
        let viewModel = ListenScreenViewModel(
            audioRecorder: StubAudioRecorder(),
            client: StubHTTPClient(handler: { _ in
                StubResponses.http(401, body: Fixtures.errorEnvelope)
            })
        )

        await viewModel.record(
            token: "stale-token",
            onUnauthorized: { await signal.fire() }
        )

        #expect(await signal.fired)
        #expect(viewModel.state == .idle)
    }

    // MARK: - Reset

    @Test func resetReturnsToIdleFromResult() async throws {
        let viewModel = ListenScreenViewModel(
            audioRecorder: StubAudioRecorder(),
            client: StubHTTPClient(handler: { _ in
                StubResponses.ok(Fixtures.recognizeSaved)
            })
        )

        await viewModel.record(token: "test-token", onUnauthorized: {})
        viewModel.reset()

        #expect(viewModel.state == .idle)
    }

    @Test func resetReturnsToIdleFromError() async throws {
        let viewModel = ListenScreenViewModel(
            audioRecorder: FailingAudioRecorder(error: .recordingFailed),
            client: StubHTTPClient(handler: { _ in throw URLError(.unknown) })
        )

        await viewModel.record(token: "test-token", onUnauthorized: {})
        viewModel.reset()

        #expect(viewModel.state == .idle)
    }

    // MARK: - Profile fetch

    @Test func loadProfileSucceedsAndPopulatesProfile() async throws {
        let viewModel = ListenScreenViewModel(
            audioRecorder: StubAudioRecorder(),
            client: StubHTTPClient(handler: { _ in
                StubResponses.ok(Fixtures.authMe)
            })
        )

        await viewModel.loadProfile(token: "test-token", onUnauthorized: {})

        #expect(viewModel.profile?.displayName == "Jamie")
        #expect(viewModel.profile?.rateLimit?.remaining == 17)
        #expect(viewModel.profile?.rateLimit?.limit == 20)
    }

    @Test func loadProfileNetworkFailureLeavesProfileNilAndStateUnchanged() async throws {
        let viewModel = ListenScreenViewModel(
            audioRecorder: StubAudioRecorder(),
            client: StubHTTPClient(handler: { _ in
                throw URLError(.notConnectedToInternet)
            })
        )

        await viewModel.loadProfile(token: "test-token", onUnauthorized: {})

        // Profile fetch failures are deliberately silent — the profile is
        // non-essential, the user can still record. No state change.
        #expect(viewModel.profile == nil)
        #expect(viewModel.state == .idle)
    }

    @Test func loadProfileUnauthorizedFiresCallback() async throws {
        let signal = UnauthorizedSignal()
        let viewModel = ListenScreenViewModel(
            audioRecorder: StubAudioRecorder(),
            client: StubHTTPClient(handler: { _ in
                StubResponses.http(401, body: Fixtures.errorEnvelope)
            })
        )

        await viewModel.loadProfile(
            token: "stale-token",
            onUnauthorized: { await signal.fire() }
        )

        #expect(await signal.fired)
        #expect(viewModel.profile == nil)
    }

    @Test func resetPreservesProfile() async throws {
        let viewModel = ListenScreenViewModel(
            audioRecorder: StubAudioRecorder(),
            client: StubHTTPClient(handler: { _ in
                StubResponses.ok(Fixtures.authMe)
            })
        )

        await viewModel.loadProfile(token: "test-token", onUnauthorized: {})
        #expect(viewModel.profile != nil)

        viewModel.reset()

        // Profile is intentionally preserved across reset so tapping
        // "Listen again" doesn't re-fetch.
        #expect(viewModel.profile != nil)
        #expect(viewModel.state == .idle)
    }

    // MARK: - Permission

    @Test func checkPermissionReadsFromRecorder() async {
        let viewModel = ListenScreenViewModel(
            audioRecorder: StubAudioRecorder(permissionStatus: .denied),
            client: StubHTTPClient(handler: { _ in throw URLError(.unknown) })
        )

        viewModel.checkPermission()

        #expect(viewModel.permissionStatus == .denied)
    }

    @Test func checkPermissionGrantedReflectsRecorderState() async {
        let viewModel = ListenScreenViewModel(
            audioRecorder: StubAudioRecorder(permissionStatus: .granted),
            client: StubHTTPClient(handler: { _ in throw URLError(.unknown) })
        )

        viewModel.checkPermission()

        #expect(viewModel.permissionStatus == .granted)
    }

    @Test func resetPreservesPermissionStatus() async {
        let viewModel = ListenScreenViewModel(
            audioRecorder: StubAudioRecorder(permissionStatus: .denied),
            client: StubHTTPClient(handler: { _ in throw URLError(.unknown) })
        )

        viewModel.checkPermission()
        #expect(viewModel.permissionStatus == .denied)

        viewModel.reset()

        // Permission status is intentionally preserved across reset.
        // Resetting recording state doesn't undo the user's grant or deny.
        #expect(viewModel.permissionStatus == .denied)
    }
}

// MARK: - Test helpers

private actor UnauthorizedSignal {
    private(set) var fired = false
    func fire() { fired = true }
}

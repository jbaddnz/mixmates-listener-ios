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
///
/// Tests use the `makeViewModel` helper to construct view models with a
/// short `recordingDuration` (0.05 seconds) and a fast `sleep` (10ms ticks)
/// so the recording timer loop completes in ~50ms wall clock rather than
/// the production 11 seconds. Tests that don't exercise the timer loop
/// (`loadProfile`, `checkPermission`, etc.) are unaffected by these
/// defaults — they're just there for the tests that do.
@Suite("ListenScreenViewModel")
@MainActor
struct ListenScreenViewModelTests {

    /// Helper that constructs a `ListenScreenViewModel` with test-friendly
    /// defaults: a `StubAudioRecorder`, a `StubHTTPClient` returning the
    /// "saved" recognition fixture, and a 50ms `recordingDuration` so the
    /// timer loop completes after roughly one iteration of the production
    /// 50ms tick (~50ms wall clock per test). Each parameter is
    /// overridable so individual tests can inject the audio recorder,
    /// HTTP handler, or duration they need.
    ///
    /// `sleep` is left at its production default (`Task.sleep(for:)`)
    /// rather than injecting a fast or no-op variant — the loop's elapsed
    /// time is measured against `Date()` (wall clock), so a no-op sleep
    /// would CPU-spin until elapsed wall-clock time hits the duration,
    /// which is wasteful. Real 50ms ticks with a 50ms duration is ~50ms
    /// of wall clock per test, which is fast enough.
    private func makeViewModel(
        audioRecorder: AudioRecording = StubAudioRecorder(),
        handler: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse) = { _ in
            StubResponses.ok(Fixtures.recognizeSaved)
        },
        recordingDuration: TimeInterval = 0.05
    ) -> ListenScreenViewModel {
        ListenScreenViewModel(
            audioRecorder: audioRecorder,
            client: StubHTTPClient(handler: handler),
            recordingDuration: recordingDuration
        )
    }

    // MARK: - Success path

    @Test func successfulRecognitionTransitionsToResult() async throws {
        let viewModel = makeViewModel()

        await viewModel.record(token: "test-token", onUnauthorized: {})

        guard case .result(let result) = viewModel.state else {
            Issue.record("Expected .result state, got \(viewModel.state)")
            return
        }
        #expect(result.status == .saved)
        #expect(result.track?.title == "Midnight City")
    }

    @Test func noMatchTransitionsToResultWithNullTrack() async throws {
        let viewModel = makeViewModel(handler: { _ in
            StubResponses.ok(Fixtures.recognizeNoMatch)
        })

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
        let viewModel = makeViewModel(
            audioRecorder: FailingAudioRecorder(error: .recordingFailed),
            handler: { _ in
                Issue.record("API should not be called when recording fails")
                throw URLError(.unknown)
            }
        )

        await viewModel.record(token: "test-token", onUnauthorized: {})

        guard case .error(let message) = viewModel.state else {
            Issue.record("Expected .error state")
            return
        }
        #expect(message.contains("Couldn't capture audio"))
    }

    @Test func permissionDeniedFromRecordUpdatesPermissionStatusAndReturnsToIdle() async throws {
        let viewModel = makeViewModel(
            audioRecorder: FailingAudioRecorder(error: .permissionDenied),
            handler: { _ in throw URLError(.unknown) }
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
        let viewModel = makeViewModel(handler: { _ in
            throw URLError(.notConnectedToInternet)
        })

        await viewModel.record(token: "test-token", onUnauthorized: {})

        guard case .error(let message) = viewModel.state else {
            Issue.record("Expected .error state")
            return
        }
        #expect(message.contains("reach MixMates"))
    }

    @Test func rateLimitedShowsTryLaterMessage() async throws {
        let viewModel = makeViewModel(handler: { _ in
            StubResponses.http(429)
        })

        await viewModel.record(token: "test-token", onUnauthorized: {})

        guard case .error(let message) = viewModel.state else {
            Issue.record("Expected .error state")
            return
        }
        #expect(message.contains("Wait a moment"))
    }

    @Test func recognitionUnavailableShowsServiceMessage() async throws {
        let viewModel = makeViewModel(handler: { _ in
            StubResponses.http(502)
        })

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
        let viewModel = makeViewModel(handler: { _ in
            StubResponses.http(401, body: Fixtures.errorEnvelope)
        })

        await viewModel.record(
            token: "stale-token",
            onUnauthorized: { await signal.fire() }
        )

        #expect(await signal.fired)
        #expect(viewModel.state == .idle)
    }

    // MARK: - Reset

    @Test func resetReturnsToIdleFromResult() async throws {
        let viewModel = makeViewModel()

        await viewModel.record(token: "test-token", onUnauthorized: {})
        viewModel.reset()

        #expect(viewModel.state == .idle)
    }

    @Test func resetReturnsToIdleFromError() async throws {
        let viewModel = makeViewModel(
            audioRecorder: FailingAudioRecorder(error: .recordingFailed),
            handler: { _ in throw URLError(.unknown) }
        )

        await viewModel.record(token: "test-token", onUnauthorized: {})
        viewModel.reset()

        #expect(viewModel.state == .idle)
    }

    // MARK: - Recording timer (slice A4)

    @Test func recordingProgressReachesOneAtCompletion() async throws {
        let viewModel = makeViewModel()

        await viewModel.record(token: "test-token", onUnauthorized: {})

        // Loop ran to completion — progress should be at 1.0 (or very
        // close, since the loop breaks on the iteration where elapsed
        // first exceeds duration).
        #expect(viewModel.recordingProgress == 1.0)
    }

    @Test func stopRecordingShortCircuitsLoopAndSubmits() async throws {
        // Use a longer recording duration so we have time to call
        // stopRecording() before the timer naturally completes.
        let viewModel = makeViewModel(recordingDuration: 5.0)

        // Spawn record() in a separate task so we can call stopRecording()
        // from the test scope while it runs.
        let recordTask = Task {
            await viewModel.record(token: "test-token", onUnauthorized: {})
        }

        // Wait for the loop to actually start ticking — polling
        // `recordingProgress > 0` proves the inner Task has been created,
        // assigned to `recordingTask`, and has executed at least one body
        // iteration. Each poll sleeps for 50ms rather than using
        // `Task.yield()` because yield returns immediately on MainActor
        // and can starve the recording task on congested CI runners —
        // the polling loop re-acquires MainActor before the recording
        // loop gets a chance to run its first 50ms tick.
        while viewModel.recordingProgress == 0.0 {
            try await Task.sleep(for: .milliseconds(50))
        }
        viewModel.stopRecording()

        // Wait for the full record flow (loop exit + stop + recognise)
        // to complete.
        await recordTask.value

        // The recognition should have happened (state should be .result)
        // even though the timer was cancelled mid-loop.
        guard case .result = viewModel.state else {
            Issue.record("Expected .result state after stopRecording, got \(viewModel.state)")
            return
        }
        // Progress did NOT reach 1.0 because we stopped early.
        #expect(viewModel.recordingProgress < 1.0)
    }

    // MARK: - Profile fetch

    @Test func loadProfileSucceedsAndPopulatesProfile() async throws {
        let viewModel = makeViewModel(handler: { _ in
            StubResponses.ok(Fixtures.authMe)
        })

        await viewModel.loadProfile(token: "test-token", onUnauthorized: {})

        #expect(viewModel.profile?.displayName == "Jamie")
        #expect(viewModel.profile?.rateLimit?.remaining == 17)
        #expect(viewModel.profile?.rateLimit?.limit == 20)
    }

    @Test func loadProfileNetworkFailureLeavesProfileNilAndStateUnchanged() async throws {
        let viewModel = makeViewModel(handler: { _ in
            throw URLError(.notConnectedToInternet)
        })

        await viewModel.loadProfile(token: "test-token", onUnauthorized: {})

        // Profile fetch failures are deliberately silent — the profile is
        // non-essential, the user can still record. No state change.
        #expect(viewModel.profile == nil)
        #expect(viewModel.state == .idle)
    }

    @Test func loadProfileUnauthorizedFiresCallback() async throws {
        let signal = UnauthorizedSignal()
        let viewModel = makeViewModel(handler: { _ in
            StubResponses.http(401, body: Fixtures.errorEnvelope)
        })

        await viewModel.loadProfile(
            token: "stale-token",
            onUnauthorized: { await signal.fire() }
        )

        #expect(await signal.fired)
        #expect(viewModel.profile == nil)
    }

    @Test func resetPreservesProfile() async throws {
        let viewModel = makeViewModel(handler: { _ in
            StubResponses.ok(Fixtures.authMe)
        })

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
        let viewModel = makeViewModel(
            audioRecorder: StubAudioRecorder(permissionStatus: .denied),
            handler: { _ in throw URLError(.unknown) }
        )

        viewModel.checkPermission()

        #expect(viewModel.permissionStatus == .denied)
    }

    @Test func checkPermissionGrantedReflectsRecorderState() async {
        let viewModel = makeViewModel(
            audioRecorder: StubAudioRecorder(permissionStatus: .granted),
            handler: { _ in throw URLError(.unknown) }
        )

        viewModel.checkPermission()

        #expect(viewModel.permissionStatus == .granted)
    }

    @Test func resetPreservesPermissionStatus() async {
        let viewModel = makeViewModel(
            audioRecorder: StubAudioRecorder(permissionStatus: .denied),
            handler: { _ in throw URLError(.unknown) }
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

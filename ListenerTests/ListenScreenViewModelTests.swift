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
/// `@MainActor`. Stub-response constructors live in a file-private free
/// namespace below for the same reason as in `TokenEntryViewModelTests` —
/// they need to be reachable from `@Sendable` `StubHTTPClient` handler
/// closures, which run from the `ListenerAPI` actor's executor (not the
/// main actor).
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

    @Test func permissionDeniedShowsAccessMessage() async throws {
        let viewModel = ListenScreenViewModel(
            audioRecorder: FailingAudioRecorder(error: .permissionDenied),
            client: StubHTTPClient(handler: { _ in throw URLError(.unknown) })
        )

        await viewModel.record(token: "test-token", onUnauthorized: {})

        guard case .error(let message) = viewModel.state else {
            Issue.record("Expected .error state")
            return
        }
        #expect(message.contains("microphone access"))
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
}

// MARK: - Stub response helpers

/// File-private free namespace for constructing canned `(Data, HTTPURLResponse)`
/// tuples. Same pattern as in `TokenEntryViewModelTests` — see that file for
/// the reasoning. (DRY note: this is the third file with this helper. A
/// future cleanup slice should extract it to a shared `StubResponses.swift`
/// in the test target.)
private enum StubResponses {

    static let url = URL(string: "https://test.example/api/v1/listener")!

    static func ok(_ json: String) -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(json.utf8), response)
    }

    static func http(
        _ status: Int,
        body: String = "",
        headers: [String: String] = [:]
    ) -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        return (Data(body.utf8), response)
    }
}

// MARK: - Test helpers

private actor UnauthorizedSignal {
    private(set) var fired = false
    func fire() { fired = true }
}

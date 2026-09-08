//
//  GoogleSignInServiceTests.swift
//  ListenerTests
//
//  Created by jamie baddeley on 09/09/2026.
//

import Foundation
import Testing
@testable import Listener

/// `@MainActor` because `GoogleSignInService` is `@MainActor` (it presents
/// UI in production). The untestable `ASWebAuthenticationSession` sits
/// behind the `sessionStarter` closure seam; these tests stub it with a
/// closure that parses the `state` out of the authorization URL and echoes
/// it back, the way Google's redirect would.
@Suite("GoogleSignInService")
@MainActor
struct GoogleSignInServiceTests {

    private let configuration = GoogleOAuthConfiguration(
        clientID: "123-ios.apps.googleusercontent.com",
        serverClientID: "123-web.apps.googleusercontent.com"
    )

    /// A session starter that behaves like Google's happy path: reads the
    /// `state` from the authorization URL and returns a callback carrying
    /// it plus the given code.
    private func echoingSession(code: String) -> GoogleSignInService.SessionStarter {
        { url, _ in
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let state = items.first(where: { $0.name == "state" })?.value ?? ""
            return URL(string: "com.googleusercontent.apps.123-ios:/oauth2redirect?code=\(code)&state=\(state)")!
        }
    }

    @Test func happyPathReturnsIDTokenAndName() async throws {
        let jwt = FakeJWT.make(payload: #"{"name":"Jane Doe","nonce":"nonce-1"}"#)
        let service = GoogleSignInService(
            configuration: configuration,
            client: StubHTTPClient(handler: { _ in StubResponses.ok(#"{"id_token":"\#(jwt)"}"#) }),
            sessionStarter: echoingSession(code: "auth-code-1")
        )

        let result = try await service.signIn(nonce: "nonce-1")

        #expect(result.idToken == jwt)
        #expect(result.displayName == "Jane Doe")
    }

    @Test func displayNameIsNilWhenGoogleOmitsTheClaim() async throws {
        let jwt = FakeJWT.make(payload: #"{"nonce":"nonce-1"}"#)
        let service = GoogleSignInService(
            configuration: configuration,
            client: StubHTTPClient(handler: { _ in StubResponses.ok(#"{"id_token":"\#(jwt)"}"#) }),
            sessionStarter: echoingSession(code: "auth-code-1")
        )

        let result = try await service.signIn(nonce: "nonce-1")

        #expect(result.displayName == nil)
    }

    @Test func exchangeRequestCarriesCodeAndAudience() async throws {
        let jwt = FakeJWT.make(payload: #"{"nonce":"nonce-1"}"#)
        let captured = CapturedRequest()
        let service = GoogleSignInService(
            configuration: configuration,
            client: StubHTTPClient(handler: { request in
                captured.set(request)
                return StubResponses.ok(#"{"id_token":"\#(jwt)"}"#)
            }),
            sessionStarter: echoingSession(code: "auth-code-1")
        )

        _ = try await service.signIn(nonce: "nonce-1")

        let body = captured.value?.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        #expect(captured.value?.url == URL(string: "https://oauth2.googleapis.com/token"))
        #expect(body.contains("code=auth-code-1"))
        #expect(body.contains("audience=123-web.apps.googleusercontent.com"))
        #expect(body.contains("code_verifier="))
    }

    @Test func nonceMismatchThrows() async {
        let jwt = FakeJWT.make(payload: #"{"nonce":"someone-elses-nonce"}"#)
        let service = GoogleSignInService(
            configuration: configuration,
            client: StubHTTPClient(handler: { _ in StubResponses.ok(#"{"id_token":"\#(jwt)"}"#) }),
            sessionStarter: echoingSession(code: "auth-code-1")
        )

        await #expect(throws: GoogleSignInError.nonceMismatch) {
            _ = try await service.signIn(nonce: "nonce-1")
        }
    }

    @Test func tokenExchangeFailurePropagatesStatusCode() async {
        let service = GoogleSignInService(
            configuration: configuration,
            client: StubHTTPClient(handler: { _ in
                StubResponses.http(400, body: #"{"error":"invalid_grant"}"#)
            }),
            sessionStarter: echoingSession(code: "expired-code")
        )

        await #expect(throws: GoogleSignInError.tokenExchangeFailed(statusCode: 400)) {
            _ = try await service.signIn(nonce: "nonce-1")
        }
    }

    @Test func cancelledSessionPropagatesSilencedError() async {
        let service = GoogleSignInService(
            configuration: configuration,
            client: StubHTTPClient(handler: { _ in StubResponses.ok("{}") }),
            sessionStarter: { _, _ in throw GoogleSignInError.cancelled }
        )

        await #expect(throws: GoogleSignInError.cancelled) {
            _ = try await service.signIn(nonce: "nonce-1")
        }
    }

    @Test func callbackWithForeignStateIsRejected() async {
        let service = GoogleSignInService(
            configuration: configuration,
            client: StubHTTPClient(handler: { _ in StubResponses.ok("{}") }),
            sessionStarter: { _, _ in
                URL(string: "com.googleusercontent.apps.123-ios:/oauth2redirect?code=auth-code-1&state=not-ours")!
            }
        )

        await #expect(throws: GoogleSignInError.invalidCallback) {
            _ = try await service.signIn(nonce: "nonce-1")
        }
    }
}

/// Thread-safe request capture for `@Sendable` stub handlers. Private copy
/// of the pattern used in `ListenerAPITests` (whose `RequestCapture` is
/// `private` to that file).
private final class CapturedRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?

    func set(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        self.request = request
    }

    var value: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }
}

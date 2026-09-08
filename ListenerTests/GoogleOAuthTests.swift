//
//  GoogleOAuthTests.swift
//  ListenerTests
//
//  Created by jamie baddeley on 09/09/2026.
//

import Foundation
import Testing
@testable import Listener

/// Non-isolated suite: `GoogleOAuth` is a namespace of pure functions over
/// value types, no actor concerns.
@Suite("GoogleOAuth helpers")
struct GoogleOAuthTests {

    private let configuration = GoogleOAuthConfiguration(
        clientID: "123-ios.apps.googleusercontent.com",
        serverClientID: "123-web.apps.googleusercontent.com"
    )

    // MARK: - Configuration

    @Test func redirectSchemeReversesClientID() {
        #expect(configuration.redirectScheme == "com.googleusercontent.apps.123-ios")
        #expect(configuration.redirectURI == "com.googleusercontent.apps.123-ios:/oauth2redirect")
    }

    // MARK: - PKCE

    @Test func codeVerifierIsURLSafeAndLongEnough() {
        let verifier = GoogleOAuth.codeVerifier()
        // RFC 7636 §4.1: 43–128 chars from the unreserved set.
        #expect(verifier.count >= 43 && verifier.count <= 128)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        #expect(verifier.unicodeScalars.allSatisfy { allowed.contains($0) })
    }

    @Test func codeVerifierIsRandomPerCall() {
        #expect(GoogleOAuth.codeVerifier() != GoogleOAuth.codeVerifier())
    }

    @Test func codeChallengeMatchesRFC7636TestVector() {
        // RFC 7636 Appendix B: the canonical verifier/challenge pair.
        let challenge = GoogleOAuth.codeChallenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    // MARK: - Authorization URL

    @Test func authorizationURLCarriesAllParameters() throws {
        let url = GoogleOAuth.authorizationURL(
            configuration: configuration,
            state: "state-1",
            nonce: "nonce-1",
            codeChallenge: "challenge-1"
        )

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "accounts.google.com")
        #expect(components.path == "/o/oauth2/v2/auth")

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value }
        #expect(query["client_id"] == "123-ios.apps.googleusercontent.com")
        #expect(query["redirect_uri"] == "com.googleusercontent.apps.123-ios:/oauth2redirect")
        #expect(query["response_type"] == "code")
        #expect(query["scope"] == "openid email profile")
        #expect(query["state"] == "state-1")
        #expect(query["nonce"] == "nonce-1")
        #expect(query["code_challenge"] == "challenge-1")
        #expect(query["code_challenge_method"] == "S256")
        // The whole reason the server accepts our tokens: aud = web client.
        #expect(query["audience"] == "123-web.apps.googleusercontent.com")
    }

    // MARK: - Callback parsing

    private func callback(_ query: String) -> URL {
        URL(string: "com.googleusercontent.apps.123-ios:/oauth2redirect?\(query)")!
    }

    @Test func callbackWithMatchingStateYieldsCode() throws {
        let code = try GoogleOAuth.authorizationCode(
            fromCallback: callback("code=auth-code-1&state=state-1"),
            expectedState: "state-1"
        )
        #expect(code == "auth-code-1")
    }

    @Test func callbackWithWrongStateThrows() {
        #expect(throws: GoogleSignInError.invalidCallback) {
            try GoogleOAuth.authorizationCode(
                fromCallback: callback("code=auth-code-1&state=evil"),
                expectedState: "state-1"
            )
        }
    }

    @Test func callbackWithoutCodeThrows() {
        #expect(throws: GoogleSignInError.invalidCallback) {
            try GoogleOAuth.authorizationCode(
                fromCallback: callback("state=state-1"),
                expectedState: "state-1"
            )
        }
    }

    @Test func consentDeniedMapsToCancelled() {
        #expect(throws: GoogleSignInError.cancelled) {
            try GoogleOAuth.authorizationCode(
                fromCallback: callback("error=access_denied&state=state-1"),
                expectedState: "state-1"
            )
        }
    }

    // MARK: - Token exchange request

    @Test func tokenExchangeRequestIsFormEncodedWithAudience() throws {
        let request = GoogleOAuth.tokenExchangeRequest(
            configuration: configuration,
            code: "4/0Ab-code",
            codeVerifier: "verifier-1"
        )

        #expect(request.url == URL(string: "https://oauth2.googleapis.com/token"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        // No custom User-Agent — the server reads the platform default.
        #expect(request.value(forHTTPHeaderField: "User-Agent") == nil)

        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        // "/" in the code must be percent-encoded in a form body.
        #expect(body.contains("code=4%2F0Ab-code"))
        #expect(body.contains("client_id=123-ios.apps.googleusercontent.com"))
        #expect(body.contains("code_verifier=verifier-1"))
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("redirect_uri=com.googleusercontent.apps.123-ios%3A%2Foauth2redirect"))
        #expect(body.contains("audience=123-web.apps.googleusercontent.com"))
    }

    // MARK: - ID token claims

    @Test func claimsDecodeNameAndNonce() throws {
        let claims = try GoogleOAuth.claims(fromIDToken: FakeJWT.make(payload: #"{"name":"Jane Doe","nonce":"n-123"}"#))
        #expect(claims.name == "Jane Doe")
        #expect(claims.nonce == "n-123")
    }

    @Test func claimsWithoutNameDecodeAsNil() throws {
        // Google never guarantees profile claims, even with the profile scope.
        let claims = try GoogleOAuth.claims(fromIDToken: FakeJWT.make(payload: #"{"nonce":"n-123","email":"j@example.com"}"#))
        #expect(claims.name == nil)
        #expect(claims.nonce == "n-123")
    }

    @Test func claimsSurviveBase64PaddingVariants() throws {
        // Payload lengths chosen so the base64url segment needs 0, 1, and 2
        // padding characters once re-padded for decoding.
        for filler in ["a", "ab", "abc", "abcd"] {
            let claims = try GoogleOAuth.claims(fromIDToken: FakeJWT.make(payload: #"{"nonce":"\#(filler)"}"#))
            #expect(claims.nonce == filler)
        }
    }

    @Test func malformedTokenThrows() {
        #expect(throws: GoogleSignInError.invalidIDToken) {
            try GoogleOAuth.claims(fromIDToken: "only.two")
        }
        #expect(throws: GoogleSignInError.invalidIDToken) {
            try GoogleOAuth.claims(fromIDToken: "header.!!!not-base64!!!.sig")
        }
    }
}

/// Builds structurally valid, unsigned JWTs for tests. Free namespace so
/// it's callable from non-isolated suites and `@Sendable` stub closures
/// alike (see `StubResponses` for the rationale).
enum FakeJWT {
    static func make(payload: String) -> String {
        let header = GoogleOAuth.base64URLEncoded(Data(#"{"alg":"RS256"}"#.utf8))
        let body = GoogleOAuth.base64URLEncoded(Data(payload.utf8))
        return "\(header).\(body).fake-signature"
    }
}

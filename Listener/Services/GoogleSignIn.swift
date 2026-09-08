//
//  GoogleSignIn.swift
//  Listener
//
//  Created by jamie baddeley on 09/09/2026.
//

import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

// MARK: - Configuration

/// The two Google OAuth client IDs the sign-in flow needs.
///
/// This app deliberately does not use the GoogleSignIn SDK (no third-party
/// dependencies, ever). Instead it drives Google's documented OAuth 2.0 /
/// OpenID Connect endpoints directly with `ASWebAuthenticationSession` —
/// the exact same system sheet the SDK itself presents, speaking the exact
/// same wire protocol. The one non-obvious ingredient, verified against the
/// SDK's source (`GIDSignIn.m`, `kAudienceParameter`): its `serverClientID`
/// feature is implemented as an extra `audience=<web client ID>` parameter
/// on both the authorization request and the token exchange, which makes
/// the minted ID token's `aud` claim the web client ID — the audience the
/// MixMates server verifies.
struct GoogleOAuthConfiguration: Sendable {

    /// The iOS-type OAuth client ID (`…apps.googleusercontent.com`). Owns
    /// the custom-scheme redirect; iOS clients are public, so no secret
    /// exists anywhere in this flow.
    let clientID: String

    /// The MixMates *web* client ID, sent as the `audience` parameter so
    /// the ID token's `aud` matches what `POST /auth/google` verifies.
    let serverClientID: String

    /// The live configuration. `nil` until both client IDs exist, which
    /// hides the Google button entirely — the branch is mergeable before
    /// the console work happens.
    ///
    /// To activate: in the Google Cloud console (MixMates project), publish
    /// the OAuth consent screen to production, create an iOS-type OAuth
    /// client for bundle `es.mixmat.listener` (no redirect-URI field — the
    /// reversed-scheme redirect is implicit), then fill in that client ID
    /// plus the existing web client ID here.
    static let current: GoogleOAuthConfiguration? = nil

    /// Reverse-DNS redirect scheme derived from the iOS client ID:
    /// `NNN-xxx.apps.googleusercontent.com` → `com.googleusercontent.apps.NNN-xxx`.
    /// No Info.plist registration is needed — `ASWebAuthenticationSession`
    /// intercepts the redirect itself.
    var redirectScheme: String {
        let suffix = ".apps.googleusercontent.com"
        let bare = clientID.hasSuffix(suffix) ? String(clientID.dropLast(suffix.count)) : clientID
        return "com.googleusercontent.apps." + bare
    }

    var redirectURI: String { redirectScheme + ":/oauth2redirect" }
}

// MARK: - Errors

enum GoogleSignInError: Error, Equatable {
    /// The user dismissed the sheet or denied consent. Callers treat this
    /// as a silent no-op, matching the Apple-cancel path.
    case cancelled
    /// The redirect came back without a code or with the wrong `state`.
    case invalidCallback
    case tokenExchangeFailed(statusCode: Int)
    /// The token endpoint's JSON or the ID token's payload didn't parse.
    case invalidIDToken
    /// The ID token's `nonce` claim didn't match the one we sent.
    case nonceMismatch
}

// MARK: - Pure OAuth helpers

/// Stateless pieces of the OAuth flow — URL building, PKCE, callback
/// parsing, JWT payload decoding. A free namespace so every piece is unit
/// testable without touching `ASWebAuthenticationSession`.
enum GoogleOAuth {

    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    /// Claims the app reads out of the ID token. The payload is decoded
    /// WITHOUT signature verification — the server is the verifier; the
    /// client only needs `name` (never guaranteed by Google, even with the
    /// `profile` scope) and `nonce` (checked as defense in depth).
    struct IDTokenClaims: Decodable, Equatable {
        let name: String?
        let nonce: String?
    }

    struct TokenResponse: Decodable {
        let idToken: String

        enum CodingKeys: String, CodingKey {
            case idToken = "id_token"
        }
    }

    /// Random base64url string from 32 bytes of system entropy (Swift's
    /// default RNG is cryptographically secure). 43 characters, drawn from
    /// `[A-Za-z0-9-_]` — inside PKCE's unreserved set and its 43–128 length
    /// window, and equally good for `state` and `nonce` values.
    static func randomURLSafeString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: .min ... .max)
        }
        return base64URLEncoded(Data(bytes))
    }

    static func codeVerifier() -> String { randomURLSafeString() }

    /// S256: base64url(SHA256(verifier)), no padding — RFC 7636 §4.2.
    static func codeChallenge(for verifier: String) -> String {
        base64URLEncoded(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func authorizationURL(
        configuration: GoogleOAuthConfiguration,
        state: String,
        nonce: String,
        codeChallenge: String
    ) -> URL {
        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "audience", value: configuration.serverClientID),
        ]
        return components.url!
    }

    /// Extract the authorization code from the redirect, enforcing the
    /// `state` round-trip (CSRF hygiene). A user who tapped "Cancel" on
    /// Google's consent screen comes back as `error=access_denied`, which
    /// maps to `.cancelled` so the UI stays silent.
    static func authorizationCode(fromCallback url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }
        if value("error") == "access_denied" {
            throw GoogleSignInError.cancelled
        }
        guard value("state") == expectedState, let code = value("code") else {
            throw GoogleSignInError.invalidCallback
        }
        return code
    }

    static func tokenExchangeRequest(
        configuration: GoogleOAuthConfiguration,
        code: String,
        codeVerifier: String
    ) -> URLRequest {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // No custom User-Agent here or anywhere: the server derives
        // sign-in attribution from the platform default (CFNetwork/Darwin).
        request.httpBody = Data(formEncoded([
            ("client_id", configuration.clientID),
            ("code", code),
            ("code_verifier", codeVerifier),
            ("grant_type", "authorization_code"),
            ("redirect_uri", configuration.redirectURI),
            ("audience", configuration.serverClientID),
        ]).utf8)
        return request
    }

    static func formEncoded(_ pairs: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return pairs
            .map { name, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(name)=\(encoded)"
            }
            .joined(separator: "&")
    }

    /// Decode the JWT payload segment (base64url, re-padded) into claims.
    static func claims(fromIDToken idToken: String) throws -> IDTokenClaims {
        let segments = idToken.split(separator: ".")
        guard segments.count == 3 else { throw GoogleSignInError.invalidIDToken }

        var base64 = segments[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }

        guard let payload = Data(base64Encoded: base64),
              let claims = try? JSONDecoder().decode(IDTokenClaims.self, from: payload) else {
            throw GoogleSignInError.invalidIDToken
        }
        return claims
    }
}

// MARK: - Service

/// What a completed Google sign-in hands back to the caller: the raw ID
/// token JWT for `POST /auth/google`, plus the display name when Google's
/// token carried one. Mirrors the Android sibling's `GoogleSignInResult`.
struct GoogleSignInResult: Equatable {
    let idToken: String
    let displayName: String?
}

/// Drives the full native Google sign-in: present the system auth sheet,
/// enforce the `state` round-trip, exchange the code for an ID token, and
/// check the `nonce` claim.
///
/// `@MainActor` because `ASWebAuthenticationSession` presents UI. The
/// session itself is the one untestable piece, so it sits behind the
/// injectable `sessionStarter` closure (house closure-seam style); the
/// token exchange goes through the existing `HTTPClient` seam.
@MainActor
final class GoogleSignInService: NSObject {

    typealias SessionStarter = @MainActor (_ url: URL, _ callbackScheme: String) async throws -> URL

    private let configuration: GoogleOAuthConfiguration
    private let client: HTTPClient
    private let sessionStarter: SessionStarter?
    private var activeSession: ASWebAuthenticationSession?

    init(
        configuration: GoogleOAuthConfiguration,
        client: HTTPClient = URLSession.shared,
        sessionStarter: SessionStarter? = nil
    ) {
        self.configuration = configuration
        self.client = client
        self.sessionStarter = sessionStarter
    }

    /// Run the whole flow. `nonce` must be freshly generated per attempt —
    /// the server replay-guards it (single-use, 5-minute window), so a
    /// retry with a reused nonce is rejected as `nonce_reused`.
    ///
    /// Throws `GoogleSignInError.cancelled` when the user backs out at any
    /// point; callers treat that silently, like the Apple-cancel path.
    func signIn(nonce: String) async throws -> GoogleSignInResult {
        let verifier = GoogleOAuth.codeVerifier()
        let state = GoogleOAuth.randomURLSafeString()
        let authURL = GoogleOAuth.authorizationURL(
            configuration: configuration,
            state: state,
            nonce: nonce,
            codeChallenge: GoogleOAuth.codeChallenge(for: verifier)
        )

        let callbackURL: URL
        if let sessionStarter {
            callbackURL = try await sessionStarter(authURL, configuration.redirectScheme)
        } else {
            callbackURL = try await presentAuthenticationSession(url: authURL)
        }

        let code = try GoogleOAuth.authorizationCode(fromCallback: callbackURL, expectedState: state)

        let request = GoogleOAuth.tokenExchangeRequest(
            configuration: configuration,
            code: code,
            codeVerifier: verifier
        )
        let (data, response) = try await client.send(request)
        guard response.statusCode == 200 else {
            throw GoogleSignInError.tokenExchangeFailed(statusCode: response.statusCode)
        }
        guard let tokenResponse = try? JSONDecoder().decode(GoogleOAuth.TokenResponse.self, from: data) else {
            throw GoogleSignInError.invalidIDToken
        }

        let claims = try GoogleOAuth.claims(fromIDToken: tokenResponse.idToken)
        guard claims.nonce == nonce else {
            throw GoogleSignInError.nonceMismatch
        }

        return GoogleSignInResult(idToken: tokenResponse.idToken, displayName: claims.name)
    }

    private func presentAuthenticationSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            // init(url:callbackURLScheme:) is deprecated from iOS 17.4 in
            // favour of init(url:callback:), which is above this project's
            // iOS 16 floor — the warning is accepted until the floor moves.
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: configuration.redirectScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let sessionError = error as? ASWebAuthenticationSessionError,
                          sessionError.code == .canceledLogin {
                    continuation.resume(throwing: GoogleSignInError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? GoogleSignInError.invalidCallback)
                }
            }
            session.presentationContextProvider = self
            // prefersEphemeralWebBrowserSession stays false: sharing
            // Safari's cookie jar means a returning user sees Google's
            // one-tap account chooser instead of a password prompt.
            activeSession = session
            if session.start() == false {
                activeSession = nil
                continuation.resume(throwing: GoogleSignInError.invalidCallback)
            }
        }
    }
}

extension GoogleSignInService: ASWebAuthenticationPresentationContextProviding {

    /// The session calls this on the main thread but the protocol
    /// requirement is nonisolated, so hop back explicitly with
    /// `assumeIsolated`. Anchoring to the key window of the active scene
    /// attaches the sheet to the visible UI.
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
            ?? ASPresentationAnchor()
        }
    }
}

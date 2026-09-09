//
//  SignInScreen.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import AuthenticationServices
import Combine
import CryptoKit
import SwiftUI

struct SignInScreen: View {

    @EnvironmentObject private var auth: AuthState
    @StateObject private var viewModel = SignInViewModel()
    @State private var currentNonce: String?

    /// A successful sign-in that minted a brand-new account, held here until
    /// the user decides whether to keep it. The token only enters `AuthState`
    /// on "Keep this account" — a second account is never adopted silently.
    @State private var pendingNewAccount: PendingSession?
    @State private var showNewAccountAlert = false

    private struct PendingSession {
        let token: String
        let method: SignInMethod
    }

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 20) {
                    Image("LaunchLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 280)
                    Text("Listener")
                        .font(.custom("HelveticaNeue", size: 36))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("MixMates Listener")

                Text("Sign in to start listening.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    SignInWithAppleButton(.signIn) { request in
                        let nonce = UUID().uuidString
                        currentNonce = nonce
                        let hashedNonce = SHA256.hash(data: Data(nonce.utf8))
                            .map { String(format: "%02x", $0) }.joined()
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = hashedNonce
                    } onCompletion: { result in
                        Task { await handleAppleSignIn(result) }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)

                    // Hidden until both Google client IDs are configured —
                    // see GoogleOAuthConfiguration.current.
                    if let googleConfiguration = GoogleOAuthConfiguration.current {
                        GoogleSignInButton {
                            Task { await handleGoogleSignIn(configuration: googleConfiguration) }
                        }
                    }

                    if let lastMethod = auth.lastSignInMethod {
                        (Text("Last time you signed in with ")
                            + Text(lastMethod.displayName).fontWeight(.bold)
                            + Text("."))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }

                    Text("Free • No in-app purchases")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .transition(.opacity)
                }

                Spacer()
            }
            .padding()
        }
        .animation(.default, value: viewModel.errorMessage)
        .alert(
            "New MixMates account created",
            isPresented: $showNewAccountAlert,
            presenting: pendingNewAccount
        ) { pending in
            Button("Sign out", role: .destructive) {
                pendingNewAccount = nil
            }
            Button("Keep this account") {
                auth.setToken(pending.token, method: pending.method)
                pendingNewAccount = nil
            }
        } message: { _ in
            Text("There was no MixMates account for this sign-in, so we made a new one. Already have an account — maybe with Apple, or another Google account? Sign out and use that instead.")
        }
    }

    /// Adopt a successful sign-in — immediately when the account already
    /// existed, or via the new-account alert when the server just created
    /// one (the fork tripwire: a person with an existing account under the
    /// other provider should get the chance to back out and use that
    /// instead).
    private func adopt(_ result: AuthResult, method: SignInMethod) {
        if result.isNewAccount {
            pendingNewAccount = PendingSession(token: result.token, method: method)
            showNewAccountAlert = true
        } else {
            auth.setToken(result.token, method: method)
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                viewModel.errorMessage = "Couldn't complete Apple sign-in. Try again."
                return
            }

            let name: String? = {
                guard let fullName = credential.fullName else { return nil }
                let parts = [fullName.givenName, fullName.familyName].compactMap { $0 }
                return parts.isEmpty ? nil : parts.joined(separator: " ")
            }()

            let email = credential.email

            if let result = await viewModel.signInWithApple(
                identityToken: identityToken,
                nonce: nonce,
                name: name,
                email: email
            ) {
                adopt(result, method: .apple)
            }

        case .failure:
            // User cancelled or system error — don't show an error for cancellation
            break
        }
    }

    private func handleGoogleSignIn(configuration: GoogleOAuthConfiguration) async {
        // Fresh nonce per attempt — the server replay-guards it (single-use,
        // 5-minute window), so retries must never reuse one.
        let nonce = UUID().uuidString
        let service = GoogleSignInService(configuration: configuration)
        do {
            let signIn = try await service.signIn(nonce: nonce)
            if let result = await viewModel.signInWithGoogle(
                idToken: signIn.idToken,
                nonce: nonce,
                name: signIn.displayName
            ) {
                adopt(result, method: .google)
            }
        } catch GoogleSignInError.cancelled {
            // User backed out of the Google sheet — silent, matching the
            // Apple-cancel path above.
        } catch {
            viewModel.errorMessage = "Couldn't complete Google sign-in. Try again."
        }
    }
}

/// View model for `SignInScreen`. Handles Sign in with Apple and Sign in
/// with Google authentication against the Listener API.
///
/// `@MainActor` because it drives a SwiftUI view. `ObservableObject` rather
/// than `@Observable` because the project's deployment target is iOS 16,
/// which predates the Observation framework.
///
/// `import Combine` is required at the top of this file because Xcode 26's
/// `MemberImportVisibility` upcoming feature no longer implicitly re-exports
/// Combine through SwiftUI.
@MainActor
final class SignInViewModel: ObservableObject {

    @Published private(set) var isVerifying = false
    @Published var errorMessage: String?

    private let client: HTTPClient
    private let baseURL: URL

    init(client: HTTPClient = URLSession.shared,
         baseURL: URL = ListenerAPI.defaultBaseURL) {
        self.client = client
        self.baseURL = baseURL
    }

    /// Authenticate via Sign in with Apple. Sends the identity token and
    /// nonce to the server, receives a bearer token. Returns the full
    /// `AuthResult` on success — the view needs `isNewAccount` for the fork
    /// tripwire — or `nil` if sign-in failed (with `errorMessage` set).
    func signInWithApple(
        identityToken: String,
        nonce: String,
        name: String?,
        email: String?
    ) async -> AuthResult? {
        await authenticate {
            try await $0.authenticateWithApple(
                identityToken: identityToken,
                nonce: nonce,
                name: name,
                email: email
            )
        }
    }

    /// Authenticate via Sign in with Google. Sends the Google ID token and
    /// the same raw nonce that went into the Google sign-in request. Returns
    /// the full `AuthResult` on success or `nil` on failure (with
    /// `errorMessage` set).
    func signInWithGoogle(
        idToken: String,
        nonce: String,
        name: String?
    ) async -> AuthResult? {
        await authenticate {
            try await $0.authenticateWithGoogle(
                idToken: idToken,
                nonce: nonce,
                name: name
            )
        }
    }

    private func authenticate(
        _ call: (ListenerAPI) async throws -> AuthResult
    ) async -> AuthResult? {
        isVerifying = true
        errorMessage = nil
        defer { isVerifying = false }

        let api = ListenerAPI(
            baseURL: baseURL,
            client: client,
            tokenProvider: { nil }
        )

        do {
            return try await call(api)
        } catch APIError.network {
            errorMessage = "Couldn't reach MixMates. Check your connection."
        } catch APIError.rateLimited {
            errorMessage = "Too many attempts. Wait a moment and try again."
        } catch {
            errorMessage = "Couldn't sign in. Try again."
        }
        return nil
    }
}

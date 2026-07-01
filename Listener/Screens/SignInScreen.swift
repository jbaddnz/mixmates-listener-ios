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

            if let token = await viewModel.signInWithApple(
                identityToken: identityToken,
                nonce: nonce,
                name: name,
                email: email
            ) {
                auth.setToken(token)
            }

        case .failure:
            // User cancelled or system error — don't show an error for cancellation
            break
        }
    }
}

/// View model for `SignInScreen`. Handles Sign in with Apple authentication.
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
    /// nonce to the server, receives a bearer token. Returns the token on
    /// success, or `nil` if sign-in failed (with `errorMessage` set).
    func signInWithApple(
        identityToken: String,
        nonce: String,
        name: String?,
        email: String?
    ) async -> String? {
        isVerifying = true
        errorMessage = nil
        defer { isVerifying = false }

        let api = ListenerAPI(
            baseURL: baseURL,
            client: client,
            tokenProvider: { nil }
        )

        do {
            let result = try await api.authenticateWithApple(
                identityToken: identityToken,
                nonce: nonce,
                name: name,
                email: email
            )
            return result.token
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

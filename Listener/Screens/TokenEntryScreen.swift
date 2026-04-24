//
//  TokenEntryScreen.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import AuthenticationServices
import Combine
import CryptoKit
import SwiftUI

struct TokenEntryScreen: View {

    @EnvironmentObject private var auth: AuthState
    @StateObject private var viewModel = TokenEntryViewModel()
    @State private var key: String = ""
    @State private var currentNonce: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("MixMates Listener")
                    .font(.largeTitle.weight(.semibold))
                Text("Sign in to start listening.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
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

                divider

                TextField("Paste Listen Key", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.go)
                    .onSubmit { Task { await verify() } }

                Button {
                    Task { await verify() }
                } label: {
                    if viewModel.isVerifying {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Verify")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isVerifying)
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
        .animation(.default, value: viewModel.errorMessage)
    }

    private var divider: some View {
        HStack {
            Rectangle().fill(.quaternary).frame(height: 1)
            Text("or")
                .font(.caption)
                .foregroundStyle(.secondary)
            Rectangle().fill(.quaternary).frame(height: 1)
        }
    }

    private func verify() async {
        if let verified = await viewModel.verify(key) {
            auth.setToken(verified)
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

/// View model for `TokenEntryScreen`. Handles both Listen Key verification
/// and Sign in with Apple authentication.
///
/// `@MainActor` because it drives a SwiftUI view. `ObservableObject` rather
/// than `@Observable` because the project's deployment target is iOS 16,
/// which predates the Observation framework.
///
/// `import Combine` is required at the top of this file because Xcode 26's
/// `MemberImportVisibility` upcoming feature no longer implicitly re-exports
/// Combine through SwiftUI.
@MainActor
final class TokenEntryViewModel: ObservableObject {

    @Published private(set) var isVerifying = false
    @Published var errorMessage: String?

    private let client: HTTPClient
    private let baseURL: URL

    init(client: HTTPClient = URLSession.shared,
         baseURL: URL = ListenerAPI.defaultBaseURL) {
        self.client = client
        self.baseURL = baseURL
    }

    /// Verify a candidate listen key against `GET /auth/me`. Returns the
    /// trimmed key on success, or `nil` if verification failed (in which
    /// case `errorMessage` is set for the view to display).
    func verify(_ key: String) async -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        isVerifying = true
        errorMessage = nil
        defer { isVerifying = false }

        let api = ListenerAPI(
            baseURL: baseURL,
            client: client,
            tokenProvider: { trimmed }
        )

        do {
            let profile = try await api.me()
            guard profile.listenEnabled else {
                errorMessage = "Listen isn't enabled for this account. Visit mixmat.es to turn it on."
                return nil
            }
            return trimmed
        } catch APIError.unauthorized {
            errorMessage = "That key isn't valid. Check it and try again."
        } catch APIError.network {
            errorMessage = "Couldn't reach MixMates. Check your connection."
        } catch APIError.rateLimited {
            errorMessage = "Too many attempts. Wait a moment and try again."
        } catch {
            errorMessage = "Couldn't verify the key. Try again."
        }
        return nil
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
            guard result.listenEnabled else {
                errorMessage = "Listen isn't enabled for this account. Visit mixmat.es to upgrade."
                return nil
            }
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

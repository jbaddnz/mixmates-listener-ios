//
//  TokenEntryScreen.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import Combine
import SwiftUI

struct TokenEntryScreen: View {

    @EnvironmentObject private var auth: AuthState
    @StateObject private var viewModel = TokenEntryViewModel()
    @State private var key: String = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("MixMates Listener")
                    .font(.largeTitle.weight(.semibold))
                Text("Paste your Listen Key to get started.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                TextField("Listen Key", text: $key)
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

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal)

            Spacer()

            Link("How to get a Listen Key",
                 destination: URL(string: "https://mixmat.es/install")!)
                .font(.footnote)
                .padding(.bottom)
        }
        .padding()
        .animation(.default, value: viewModel.errorMessage)
    }

    private func verify() async {
        if let verified = await viewModel.verify(key) {
            auth.setToken(verified)
        }
    }
}

/// View model for `TokenEntryScreen`.
///
/// `@MainActor` because it drives a SwiftUI view. `ObservableObject` rather
/// than `@Observable` because the project's deployment target is iOS 16,
/// which predates the Observation framework, and the no-third-party-dependencies
/// rule rules out backports like Point-Free's Perception. Migrate to
/// `@Observable` when the project drops iOS 16 support and the floor moves
/// to iOS 17+.
///
/// `import Combine` is required at the top of this file because Xcode 26's
/// `MemberImportVisibility` upcoming feature no longer implicitly re-exports
/// Combine through SwiftUI.
@MainActor
final class TokenEntryViewModel: ObservableObject {

    @Published private(set) var isVerifying = false
    @Published private(set) var errorMessage: String?

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
}

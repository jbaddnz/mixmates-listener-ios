//
//  AlternateAccountScreen.swift
//  Listener
//
//  Created by jamie baddeley on 13/05/2026.
//

import Combine
import SwiftUI

/// Presented as a sheet from `SettingsScreen`. Lets a user authenticate as
/// a different MixMates account by pasting that account's Listen Key.
///
/// This is account selection, not feature unlock. The iOS app's feature
/// set is identical for every authenticated user — pasting a different
/// account's key just changes whose listening session this device logs.
/// Used by venue staff, event volunteers, or operators running multiple
/// MixMates accounts on one device.
struct AlternateAccountScreen: View {

    @EnvironmentObject private var auth: AuthState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AlternateAccountViewModel()
    @State private var key: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("Enter a Listen Key to log tracks under a different MixMates account. Useful for venue staff, event volunteers, or operating multiple accounts on one device.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                VStack(spacing: 12) {
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
                            Text("Switch account")
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
            .padding(.top, 24)
            .navigationTitle("Use alternate MixMates account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .animation(.default, value: viewModel.errorMessage)
        }
    }

    private func verify() async {
        if let verified = await viewModel.verify(key) {
            auth.setToken(verified)
            dismiss()
        }
    }
}

/// View model for `AlternateAccountScreen`. Reuses the same `/auth/me`
/// verification logic the entry screen previously used for Listen Key
/// authentication — relocated here because the Listen Key paste is now an
/// account-selection affordance, not an entry-screen auth path.
///
/// `@MainActor` because it drives a SwiftUI view. `ObservableObject` rather
/// than `@Observable` because the project's deployment target is iOS 16.
/// `import Combine` required because Xcode 26's `MemberImportVisibility`
/// upcoming feature no longer implicitly re-exports Combine through SwiftUI.
@MainActor
final class AlternateAccountViewModel: ObservableObject {

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
                errorMessage = "Listen isn't enabled for that account."
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

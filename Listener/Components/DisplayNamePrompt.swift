//
//  DisplayNamePrompt.swift
//  Listener
//

import SwiftUI

/// The single field shown when a share is refused because the account has
/// no display name of its own yet.
///
/// Shown inline, in place of the group picker, rather than as a sheet on top
/// of the share sheet: the person is in the middle of sharing, and the name
/// is one step of that, not a detour. Used by both the app's share sheet and
/// the Share Extension.
struct DisplayNamePrompt: View {

    @Binding var name: String
    let isSaving: Bool
    let error: String?
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    private var canSubmit: Bool {
        UserProfile.validDisplayName(name) != nil && !isSaving
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ShareFlowCopy.namePrompt)
                    .font(.headline)
                Text(ShareFlowCopy.nameHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            TextField(ShareFlowCopy.namePlaceholder, text: $name)
                .textFieldStyle(.roundedBorder)
                .textContentType(.nickname)
                .submitLabel(.done)
                .focused($isFocused)
                .disabled(isSaving)
                .onSubmit {
                    if canSubmit { onSubmit() }
                }

            Button(action: onSubmit) {
                if isSaving {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(ShareFlowCopy.nameSubmit)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(ShareFlowCopy.nameCancel, action: onCancel)
                .font(.callout)
                .disabled(isSaving)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { isFocused = true }
    }
}

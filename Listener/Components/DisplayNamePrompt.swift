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

    /// "Save and share" when a share is waiting on the name, "Save" when it
    /// is starting a group.
    var submitLabel: String = ShareFlowCopy.nameSubmit

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
                // Capped as it is typed, so an over-long name stops growing
                // rather than leaving a button disabled for no visible reason.
                .onChange(of: name) { newValue in
                    if newValue.count > UserProfile.displayNameMaxLength {
                        name = String(newValue.prefix(UserProfile.displayNameMaxLength))
                    }
                }

            Button(action: onSubmit) {
                Group {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(submitLabel)
                    }
                }
                // Full strength while saving: the spinner already says it
                // is working.
                .brandCapsule(looksEnabled: canSubmit || isSaving)
            }
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

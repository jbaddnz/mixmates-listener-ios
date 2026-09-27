//
//  NotificationAskCard.swift
//  Listener
//

import SwiftUI

/// Asks, in the app's own voice, before the system prompt appears.
///
/// The iOS permission alert is one-shot: a refusal puts the account in
/// `.denied` for good and the only way back is the Settings app. So the
/// reason comes first, in a card that can be waved away at no cost, and the
/// real prompt is only raised by someone who has already said yes to the
/// idea. This is the standard pre-permission pattern, and the card is
/// deliberately not styled to resemble a system alert.
///
/// Copy stands alone. It says what the notification is for and nothing else.
struct NotificationAskCard: View {

    let onTurnOn: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Know when friends share", systemImage: "bell.badge")
                .font(.callout.weight(.semibold))

            Text("Get a notification when someone adds a track to one of your groups.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Turn on", action: onTurnOn)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.mixmatesCyan)
                Button("Not now", action: onNotNow)
                    .buttonStyle(.bordered)
            }
            .font(.callout)
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        }
    }
}

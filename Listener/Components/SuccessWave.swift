//
//  SuccessWave.swift
//  Listener
//
//  Created by jamie baddeley on 09/09/2026.
//

import SwiftUI

/// The recognition-success celebration: a small green-to-cyan soundwave —
/// the brand's signature device for a song travelling between people. On
/// appear the bars pulse for ~1.2 seconds, then settle into a static wave.
///
/// Respects Reduce Motion: the bars render directly in their settled
/// arrangement with no animation.
struct SuccessWave: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    /// Bar heights as fractions of the full height — a loose wave shape.
    private static let settledHeights: [CGFloat] = [0.45, 0.85, 0.60, 1.00, 0.50]
    private static let pulseHeights: [CGFloat] = [0.25, 0.50, 0.30, 0.55, 0.30]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<Self.settledHeights.count, id: \.self) { index in
                Capsule()
                    .fill(LinearGradient.mixmatesBrand)
                    .frame(
                        width: 6,
                        height: 36 * (settled ? Self.settledHeights[index] : Self.pulseHeights[index])
                    )
            }
        }
        .frame(height: 36)
        // Odd repeat count with autoreverse ends the bounce on the settled
        // heights instead of snapping.
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.25).repeatCount(5, autoreverses: true),
            value: settled
        )
        .onAppear { settled = true }
        .accessibilityHidden(true)
    }
}

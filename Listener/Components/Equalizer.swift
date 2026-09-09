//
//  Equalizer.swift
//  Listener
//
//  Created by jamie baddeley on 09/09/2026.
//

import SwiftUI

/// The brand's shared working-state animation, replicated exactly from the
/// web app (see `docs/plans/proposed/listener-equalizer-shared-visual.md`
/// in the mixmates repo — the same spec drives web, iOS, and Android, so
/// all three surfaces share one heartbeat).
///
/// Five bottom-anchored bars in the green-to-cyan journey colours, each
/// cycling 6 → 28 → 6 (at web scale) over 1.0 s ease-in-out, forever, with
/// a 0.15 s stagger per bar left to right — the stagger is what makes the
/// wave roll. Plays while the system is doing the musical work (here: the
/// identifying window); it is a working indicator, not a success state.
///
/// `scale` preserves the spec's ratios (bar : gap : height = 4 : 3 : 28)
/// at other sizes. Time is absolute and never scales. Under Reduce Motion
/// the bars render static at staggered heights so the brand mark survives
/// without motion.
struct Equalizer: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var scale: CGFloat = 1

    /// Exact and ordered left to right — the green-to-cyan journey. Do not
    /// reorder.
    private static let colors: [Color] = [
        Color(red: 0x1D / 255, green: 0xB9 / 255, blue: 0x54 / 255),  // #1DB954
        Color(red: 0x1E / 255, green: 0xD7 / 255, blue: 0x60 / 255),  // #1ED760
        Color(red: 0x33 / 255, green: 0xCC / 255, blue: 0x99 / 255),  // #33CC99
        Color(red: 0x00 / 255, green: 0xD4 / 255, blue: 0xFF / 255),  // #00D4FF
        Color(red: 0x00 / 255, green: 0xB4 / 255, blue: 0xD8 / 255),  // #00B4D8
    ]

    /// Reduce Motion fallback: static staggered heights (web-scale values
    /// from the spec).
    private static let staticHeights: [CGFloat] = [10, 18, 28, 18, 10]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3 * scale) {
            ForEach(0..<Self.colors.count, id: \.self) { index in
                Capsule()
                    .fill(Self.colors[index])
                    .frame(width: 4 * scale, height: barHeight(index))
                    // 0.5 s each way = the spec's 1.0 s full cycle. The
                    // per-bar delay applies once at start, so the phase
                    // offset persists through every repeat.
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(0.15 * Double(index)),
                        value: animating
                    )
            }
        }
        .frame(height: 32 * scale, alignment: .bottom)
        .onAppear { animating = true }
        // Decorative — the accompanying text carries the meaning.
        .accessibilityHidden(true)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        if reduceMotion { return Self.staticHeights[index] * scale }
        return (animating ? 28 : 6) * scale
    }
}

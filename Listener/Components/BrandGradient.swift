//
//  BrandGradient.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import SwiftUI

extension Color {
    /// The canonical MixMates cyan, #2CCCD3. Adjudicated across the web app,
    /// Android and here, so it is a fixed brand value rather than a local
    /// choice. It is the gradient's endpoint and is also used on its own for
    /// solid brand accents.
    static let mixmatesCyan = Color(red: 44 / 255, green: 204 / 255, blue: 211 / 255)

    /// Spotify green, the gradient's start point.
    static let mixmatesGreen = Color(red: 29 / 255, green: 185 / 255, blue: 84 / 255)
}

/// MixMates brand gradient: Spotify-green to cyan, leading-to-trailing.
/// Used by the Listen screen mic button (`Circle().fill(...)`) and the
/// recording-progress ring stroke.
extension LinearGradient {
    static let mixmatesBrand = LinearGradient(
        colors: [.mixmatesGreen, .mixmatesCyan],
        startPoint: .leading,
        endPoint: .trailing
    )
}

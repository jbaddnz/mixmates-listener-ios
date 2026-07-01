//
//  BrandGradient.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import SwiftUI

/// MixMates brand gradient: Spotify-green to cyan, leading-to-trailing.
/// Used by the Listen screen mic button (`Circle().fill(...)`) and the
/// recording-progress ring stroke.
extension LinearGradient {
    static let mixmatesBrand = LinearGradient(
        colors: [
            Color(red: 29 / 255, green: 185 / 255, blue: 84 / 255),  // Spotify green
            Color(red: 44 / 255, green: 204 / 255, blue: 211 / 255)  // cyan
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

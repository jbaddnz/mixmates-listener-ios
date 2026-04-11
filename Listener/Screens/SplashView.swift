//
//  SplashView.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import SwiftUI

/// Splash screen shown for at least 1 second after the OS-level
/// `UILaunchScreen` finishes, when the user has not opted out via Settings.
///
/// The OS launch screen handles the cold-start moment from icon-tap until
/// the app process is ready (potentially milliseconds), then this view
/// continues the brand experience for the remaining time so the user has
/// a chance to register the splash. This is the standard iOS pattern for
/// "minimum splash duration" — Apple Music, Twitter, and most major iOS
/// apps that want a non-flash splash do it this way. There is no API to
/// extend the OS launch screen itself.
///
/// Visually identical to `Assets.xcassets/LaunchLogo` on the
/// `LaunchBackground` colour fill — the OS launch screen and this view are
/// indistinguishable to the user, which is the point.
struct SplashView: View {

    /// How long the SwiftUI splash holds before transitioning to the real
    /// content. Tunable here rather than scattered through `ContentView`.
    static let duration: Duration = .seconds(1)

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()
            Image("LaunchLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 240, height: 240)
                .accessibilityLabel("MixMates Listener")
        }
    }
}

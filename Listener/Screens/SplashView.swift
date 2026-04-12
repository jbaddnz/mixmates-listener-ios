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
/// The OS launch screen is intentionally **just the `LaunchBackground`
/// colour**, no image — see `Info.plist`. The two-path design (OS launch
/// screen with logo + SwiftUI splash with logo) was tried first but the
/// OS launch screen's centred-at-native-point-size rendering didn't match
/// the SwiftUI splash's `.frame + .fit` rendering, even when both pointed
/// at the same asset, even with a 240×240 vector PDF that should have
/// matched. Rather than fight `UILaunchScreen`'s opaque rendering rules,
/// the launch screen is now a fast brand-colour flash and this SwiftUI
/// view is the *only* surface that displays the logo. Many polished iOS
/// apps work this way (Apple Music itself uses a solid-colour launch
/// screen). The 1-second hold here gives the logo enough time to register
/// before the main UI takes over.
struct SplashView: View {

    /// How long the SwiftUI splash holds before transitioning to the real
    /// content. Tunable here rather than scattered through `ContentView`.
    static let duration: Duration = .seconds(1)

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()
            VStack(spacing: 20) {
                Image("LaunchLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 320)
                Text("Listener")
                    .font(.custom("HelveticaNeue", size: 36))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("MixMates Listener")
        }
    }
}

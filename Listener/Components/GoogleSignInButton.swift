//
//  GoogleSignInButton.swift
//  Listener
//
//  Created by jamie baddeley on 09/09/2026.
//

import SwiftUI

/// "Sign in with Google" button following Google's branding guidelines
/// (light theme): white fill, 1px `#747775` stroke, `#1F1F1F` text, the
/// official multicolor G never recolored. The guidelines name Google Sans
/// Medium, which can't be bundled (licensing + the no-dependency rule) —
/// the system font at `.medium` stands in, a minor and commonly accepted
/// deviation. Sized to sit directly under the 50pt `SignInWithAppleButton`
/// at equal prominence (SIWA stays on top — guideline 4.8).
struct GoogleSignInButton: View {

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image("GoogleLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                Text("Sign in with Google")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color(red: 31 / 255, green: 31 / 255, blue: 31 / 255))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        Color(red: 116 / 255, green: 119 / 255, blue: 117 / 255),
                        lineWidth: 1
                    )
            )
        }
    }
}

//
//  ContentView.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import SwiftUI

/// Root view. Switches between `TokenEntryScreen` (signed out) and
/// `ListenScreen` (signed in) based on the observed `AuthState`. The auth
/// state lives in the SwiftUI environment so child views can sign out
/// without reaching back through navigation.
///
/// `Group { ... }` here is `SwiftUI.Group`, the view builder. Naming the
/// MixMates user-group domain type `HumanGroup` (rather than `Group`) keeps
/// this from being shadowed — see `Listener/Models/HumanGroup.swift`.
struct ContentView: View {

    @EnvironmentObject private var auth: AuthState

    var body: some View {
        Group {
            if auth.token != nil {
                ListenScreen()
            } else {
                TokenEntryScreen()
            }
        }
        .animation(.default, value: auth.token)
    }
}

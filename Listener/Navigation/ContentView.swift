//
//  ContentView.swift
//  Listener
//
//  Created by jamie baddeley on 11/04/2026.
//

import SwiftUI

/// Root view. On launch, briefly shows `SplashView` (unless the user has
/// turned the splash off in Settings), then switches between
/// `TokenEntryScreen` (signed out) and a `NavigationStack` rooted at
/// `ListenScreen` (signed in) based on the observed `AuthState`. The auth
/// state lives in the SwiftUI environment so child views can sign out
/// without reaching back through navigation.
///
/// When `AuthState.signOut()` flips `token` to `nil` (either explicitly from
/// the Settings screen or automatically via the API client's 401 callback),
/// the entire `NavigationStack` is discarded and replaced by `TokenEntryScreen`,
/// regardless of how deep the user had pushed. No manual pop logic needed —
/// SwiftUI handles the unwinding by re-rendering the body.
///
/// The splash hold uses `@AppStorage` rather than an `ObservableObject`
/// wrapper because it's a single boolean preference shared between
/// `ContentView` (the gate) and `SettingsScreen` (the toggle binding) — for
/// one preference, the built-in pattern is the iOS-native answer. If a
/// second user preference is added later, refactor to a dedicated
/// observable.
///
/// `Group { ... }` here is `SwiftUI.Group`, the view builder. Naming the
/// MixMates user-group domain type `HumanGroup` (rather than `Group`) keeps
/// this from being shadowed — see `Listener/Models/HumanGroup.swift`.
struct ContentView: View {

    @EnvironmentObject private var auth: AuthState
    @AppStorage("showSplashScreen") private var showSplashEnabled: Bool = true
    @State private var splashFinished = false

    var body: some View {
        Group {
            if showSplashEnabled && !splashFinished {
                SplashView()
                    .task {
                        // Hold the splash for the full duration. If the task
                        // is cancelled (e.g. SwiftUI re-evaluates the view
                        // identity for any reason), do NOT flip
                        // `splashFinished` — that would prematurely transition
                        // out of the splash and the user would see a flash
                        // instead of the splash. Only flip on a clean
                        // completion of the sleep.
                        do {
                            try await Task.sleep(for: SplashView.duration)
                            splashFinished = true
                        } catch {
                            // Cancelled — leave `splashFinished` as-is. The
                            // view is going away anyway, or it'll get a fresh
                            // task on the next render.
                        }
                    }
            } else if auth.token != nil {
                NavigationStack {
                    ListenScreen()
                }
            } else {
                TokenEntryScreen()
            }
        }
        .animation(.default, value: splashFinished)
        .animation(.default, value: auth.token)
    }
}

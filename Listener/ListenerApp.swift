//
//  ListenerApp.swift
//  Listener
//
//  Created by jamie baddeley on 10/04/2026.
//

import SwiftUI
import UserNotifications

@main
struct ListenerApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var auth: AuthState
    @StateObject private var pushManager: PushManager

    init() {
        let keychain = KeychainManager(accessGroup: KeychainManager.sharedAccessGroup)
        // Migrate any token stored without an access group (v1.0) into the
        // shared group so the Share Extension can read it. No-op on fresh
        // installs or if migration has already run.
        try? keychain.migrateFromPrivateKeychain()

        let authState = AuthState(storage: keychain)
        _auth = StateObject(wrappedValue: authState)

        let push = PushManager(
            tokenProvider: { await authState.token },
            onUnauthorized: { @MainActor in authState.signOut() }
        )
        _pushManager = StateObject(wrappedValue: push)

        UNUserNotificationCenter.current().delegate = push
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(pushManager)
                .task {
                    await pushManager.registerOnLaunchIfNeeded()
                    // Cold launch from a badged icon. `onChange` below doesn't
                    // fire for the initial scene phase, so launching straight
                    // into `.active` would otherwise leave the badge sitting
                    // there while the user is looking at the app.
                    await pushManager.clearBadge()
                }
                .onChange(of: scenePhase) { newPhase in
                    // Returning to the app means the user has seen it, so the
                    // "something arrived" indicator has done its job. Handled
                    // app-wide rather than per-screen, and this also covers
                    // notification taps — a tap foregrounds the app, so the
                    // tap handler needs no clearing of its own.
                    if newPhase == .active {
                        Task { await pushManager.clearBadge() }
                    }
                }
                .onAppear { appDelegate.pushManager = pushManager }
        }
    }
}

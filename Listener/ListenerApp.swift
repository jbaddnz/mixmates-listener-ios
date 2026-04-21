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
                .task { await pushManager.registerOnLaunchIfNeeded() }
                .onAppear { appDelegate.pushManager = pushManager }
        }
    }
}

//
//  ListenerApp.swift
//  Listener
//
//  Created by jamie baddeley on 10/04/2026.
//

import SwiftUI

@main
struct ListenerApp: App {

    @StateObject private var auth: AuthState

    init() {
        let keychain = KeychainManager(accessGroup: KeychainManager.sharedAccessGroup)
        // Migrate any token stored without an access group (v1.0) into the
        // shared group so the Share Extension can read it. No-op on fresh
        // installs or if migration has already run.
        try? keychain.migrateFromPrivateKeychain()
        _auth = StateObject(wrappedValue: AuthState(storage: keychain))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
        }
    }
}

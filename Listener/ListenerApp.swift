//
//  ListenerApp.swift
//  Listener
//
//  Created by jamie baddeley on 10/04/2026.
//

import SwiftUI

@main
struct ListenerApp: App {

    @StateObject private var auth = AuthState(storage: KeychainManager())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
        }
    }
}

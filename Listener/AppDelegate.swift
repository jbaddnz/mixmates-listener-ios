//
//  AppDelegate.swift
//  Listener
//
//  Created by jamie baddeley on 21/04/2026.
//

import UIKit

/// Minimal `UIApplicationDelegate` to receive APNs device token callbacks.
/// SwiftUI has no native hooks for `didRegisterForRemoteNotifications`, so
/// this bridge is required.
///
/// `PushManager` is injected after creation because `@UIApplicationDelegateAdaptor`
/// creates the delegate before the SwiftUI body runs — init injection isn't possible.
class AppDelegate: NSObject, UIApplicationDelegate {

    var pushManager: PushManager?

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { await pushManager?.handleDeviceToken(deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Push is optional functionality — log but don't surface.
    }
}

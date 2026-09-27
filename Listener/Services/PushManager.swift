//
//  PushManager.swift
//  Listener
//
//  Created by jamie baddeley on 21/04/2026.
//

import Combine
import Foundation
import UIKit
import UserNotifications

/// Owns the APNs registration lifecycle: permission prompts, device token
/// registration with the server, deregistration on sign-out, and notification
/// tap handling.
///
/// `@MainActor` because it drives UI state (`permissionStatus`) and
/// `UNUserNotificationCenterDelegate` callbacks arrive on the main thread.
/// `NSObject` because `UNUserNotificationCenterDelegate` requires
/// `NSObjectProtocol` conformance.
///
/// `import Combine` is required because Xcode 26's `MemberImportVisibility`
/// upcoming feature no longer implicitly re-exports Combine through SwiftUI.
@MainActor
final class PushManager: NSObject, ObservableObject {

    @Published private(set) var permissionStatus: UNAuthorizationStatus = .notDetermined

    private let tokenProvider: @Sendable () async -> String?
    private let onUnauthorized: @Sendable () async -> Void
    private let client: HTTPClient

    init(
        tokenProvider: @Sendable @escaping () async -> String?,
        onUnauthorized: @Sendable @escaping () async -> Void,
        client: HTTPClient = URLSession.shared
    ) {
        self.tokenProvider = tokenProvider
        self.onUnauthorized = onUnauthorized
        self.client = client
        super.init()
    }

    // MARK: - Permission

    /// Request notification permission and register for APNs if granted.
    /// Call after the user's first successful recognition, not on launch.
    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            permissionStatus = granted ? .authorized : .denied
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            permissionStatus = .denied
        }
    }

    /// Refresh the current permission status without prompting. Call on
    /// launch to sync `permissionStatus` with the system setting (the user
    /// may have changed it in Settings since last run).
    func refreshPermissionStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permissionStatus = settings.authorizationStatus
    }

    // MARK: - Token lifecycle

    /// Convert raw APNs token data to a hex string and register it with
    /// the server. Called from `AppDelegate.didRegisterForRemoteNotifications`.
    /// Best-effort — if the server call fails, the token will be re-sent
    /// next cold launch.
    func handleDeviceToken(_ tokenData: Data) async {
        let hex = deviceTokenHexString(from: tokenData)
        let api = makeAPI()
        do {
            try await api.registerPush(deviceToken: hex)
        } catch {
            // Best-effort. Server upserts, so next launch will retry.
        }
    }

    /// Deregister all device tokens for this user from the server.
    /// Call before sign-out. Best-effort — server-side APNs feedback
    /// handles stale tokens as a fallback.
    func deregister() async {
        let api = makeAPI()
        do {
            try await api.deregisterPush()
        } catch {
            // Best-effort. Stale tokens expire via APNs feedback.
        }
    }

    /// Re-register for APNs on cold launch if the user has previously
    /// granted permission. Tokens can change between launches.
    func registerOnLaunchIfNeeded() async {
        await refreshPermissionStatus()
        if permissionStatus == .authorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    // MARK: - Badge

    /// Clear the home-screen icon badge.
    ///
    /// The server sends `aps.badge: 1` as a plain "something arrived since you
    /// last opened the app" indicator rather than an unread count. A real count
    /// can't work against this clearing model: the badge is cleared locally and
    /// the server is never told, so a server-held count would keep counting and
    /// re-badge with a stale number. If the number ever needs to be accurate,
    /// that's a read-state feature (a mark-read call), not a bigger payload.
    ///
    /// No availability branch needed: `setBadgeCount(_:)` is iOS 16.0+ (checked
    /// against the SDK header, `API_AVAILABLE(ios(16.0))`), which is exactly
    /// this app's deployment target. It's easy to assume it's 17+ because that
    /// is when the older `UIApplication.applicationIconBadgeNumber` was
    /// deprecated — but the replacement shipped a year earlier, so the
    /// deprecated API is never needed here.
    ///
    /// Best-effort — a failure here leaves a stale badge, which is cosmetic.
    func clearBadge() async {
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(0)
        } catch {
            // Best-effort. Next foreground will try again.
        }
    }

    // MARK: - Private

    private func makeAPI() -> ListenerAPI {
        ListenerAPI(
            client: client,
            tokenProvider: tokenProvider,
            onUnauthorized: onUnauthorized
        )
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushManager: UNUserNotificationCenterDelegate {

    /// Called when the user taps a notification. Extracts the `url` field
    /// from the payload and opens it in Safari.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo["url"] as? String,
           let url = URL(string: urlString) {
            Task { @MainActor in
                UIApplication.shared.open(url)
            }
        }
        completionHandler()
    }

    /// Show notifications even when the app is in the foreground.
    ///
    /// `.badge` is deliberately omitted: the user is already looking at the
    /// app, so badging the icon for a notification that arrived on-screen
    /// would leave an indicator pointing at something already seen. Leaving it
    /// out means an in-app arrival never badges. Don't "fix" this.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Helpers

/// Convert raw APNs device token data to a lowercase hex string.
/// Free function so tests can call it without MainActor isolation.
func deviceTokenHexString(from tokenData: Data) -> String {
    tokenData.map { String(format: "%02x", $0) }.joined()
}

import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// Mirror of meinchat's one-shot push-authorization prompt (S67.2 §3.6).
/// Own UserDefaults key so either plugin can run standalone; when both are
/// installed the second `requestAuthorization` resolves silently with the
/// already-decided status — no double prompt.
@MainActor
enum MeinChatPlusNotificationPermissions {
    static let askedDefaultsKey = "meinchat-plus.notifications.askOnce"

    static func askOnce(defaults: UserDefaults = .standard) async {
        guard !defaults.bool(forKey: askedDefaultsKey) else { return }
        defaults.set(true, forKey: askedDefaultsKey)
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        guard granted else { return }
        #if canImport(UIKit) && !os(watchOS)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }
}

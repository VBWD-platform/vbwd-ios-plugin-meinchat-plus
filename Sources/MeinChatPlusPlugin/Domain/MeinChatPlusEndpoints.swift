import Foundation

/// API paths for the meinchat-plus wire contract (S28.3b §2). The vbwd-fe-user
/// web client posts to the same routes — keep this list in sync there.
enum MeinChatPlusEndpoints {
    // Device registry
    static let myDevices = "/me/devices"
    static func device(id: String) -> String { "/me/devices/\(id)" }
    static func userDevices(userId: String) -> String { "/messaging/users/\(userId)/devices" }
    static func bundle(userId: String, deviceId: String) -> String {
        "/messaging/users/\(userId)/devices/\(deviceId)/bundle"
    }

    // Prekey management
    static let signedPrekey = "/me/prekeys/signed"
    static let oneTimePrekeys = "/me/prekeys/one-time"
    static let prekeyStatus = "/me/prekeys/status"
}

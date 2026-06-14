import Foundation
import VBWDCore

/// APNs device-token registration for the meinchat-plus app surface
/// (S67.2 §3.6 — mirror of meinchat's wire contract with `app:
/// "meinchat-plus"`). Distinct from `DeviceRegistryService`, which manages
/// Signal protocol devices.
protocol PushRegistrationServiceProtocol: Sendable {
    /// Idempotent upsert server-side; requires an authenticated session.
    func registerDeviceToken(_ tokenHex: String, app: String) async throws
    /// Owner-only delete. Callers treat failures as silent.
    func unregisterDeviceToken(_ tokenHex: String) async throws
}

final class DefaultPushRegistrationService: PushRegistrationServiceProtocol, @unchecked Sendable {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func registerDeviceToken(_ tokenHex: String, app: String) async throws {
        struct Body: Encodable {
            let token: String
            let platform: String
            let bundle_id: String
            let app: String
        }
        let _: EmptyResponse = try await api.post(
            MeinChatPlusEndpoints.deviceRegister,
            body: Body(token: tokenHex,
                       platform: "ios",
                       bundle_id: Bundle.main.bundleIdentifier ?? "",
                       app: app))
    }

    func unregisterDeviceToken(_ tokenHex: String) async throws {
        let _: EmptyResponse = try await api.delete(
            MeinChatPlusEndpoints.deviceUnregister(token: tokenHex))
    }
}

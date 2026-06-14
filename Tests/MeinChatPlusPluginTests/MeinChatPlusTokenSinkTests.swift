import Testing
import Foundation
import VBWDCore
@testable import MeinChatPlusPlugin

/// S67.2 — meinchat-plus mirror of the meinchat token sink
/// (app `"meinchat-plus"`, same auth-aware buffering semantics).
struct MeinChatPlusTokenSinkTests {

    final class FakePushRegistrationService: PushRegistrationServiceProtocol, @unchecked Sendable {
        var registered: [(token: String, app: String)] = []
        var unregistered: [String] = []

        func registerDeviceToken(_ tokenHex: String, app: String) async throws {
            registered.append((token: tokenHex, app: app))
        }

        func unregisterDeviceToken(_ tokenHex: String) async throws {
            unregistered.append(tokenHex)
        }
    }

    @Test
    func forwards_token_to_service_register_with_plus_app() async {
        let service = FakePushRegistrationService()
        let sink = MeinChatPlusTokenSink(service: service)
        await sink.handleLogin()
        await sink.handleDeviceToken("aa11")
        #expect(service.registered.count == 1)
        #expect(service.registered.first?.token == "aa11")
        #expect(service.registered.first?.app == "meinchat-plus")
    }

    @Test
    func buffers_token_until_login() async {
        let service = FakePushRegistrationService()
        let sink = MeinChatPlusTokenSink(service: service)
        await sink.handleDeviceToken("aa11")
        #expect(service.registered.isEmpty)
        await sink.handleLogin()
        #expect(service.registered.map(\.token) == ["aa11"])
    }

    @Test
    func replays_token_for_late_registered_sink() async {
        let service = FakePushRegistrationService()
        let notifications = DefaultNotificationsSDK(badgeSetter: { _ in })
        await notifications.didReceiveDeviceToken("bb22")

        let sink = MeinChatPlusTokenSink(service: service)
        await sink.handleLogin()
        await notifications.registerSink(sink)

        #expect(service.registered.map(\.token) == ["bb22"])
    }

    @Test
    func unregister_called_on_logout() async {
        let service = FakePushRegistrationService()
        let sink = MeinChatPlusTokenSink(service: service)
        await sink.handleLogin()
        await sink.handleDeviceToken("cc33")
        await sink.handleLogout()
        #expect(service.unregistered == ["cc33"])
    }
}

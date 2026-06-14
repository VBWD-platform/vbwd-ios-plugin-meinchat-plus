import Foundation
import VBWDCore

/// Mirror of meinchat's token sink for the `meinchat-plus` app surface
/// (S67.2 §3.6). Buffers the APNs token until login so the register POST
/// always carries a JWT; best-effort unregisters on logout.
actor MeinChatPlusTokenSink: DeviceTokenSink {
    private let service: PushRegistrationServiceProtocol
    private let app = "meinchat-plus"
    private var lastTokenHex: String?
    private var isAuthenticated = false

    init(service: PushRegistrationServiceProtocol) {
        self.service = service
    }

    func handleDeviceToken(_ tokenHex: String) async {
        lastTokenHex = tokenHex
        guard isAuthenticated else { return }
        try? await service.registerDeviceToken(tokenHex, app: app)
    }

    func handleLogin() async {
        isAuthenticated = true
        if let tokenHex = lastTokenHex {
            try? await service.registerDeviceToken(tokenHex, app: app)
        }
    }

    func handleLogout() async {
        isAuthenticated = false
        if let tokenHex = lastTokenHex {
            try? await service.unregisterDeviceToken(tokenHex)
        }
    }
}

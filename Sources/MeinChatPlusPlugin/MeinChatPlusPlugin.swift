import SwiftUI
import VBWDCore
import MeinChatPlugin

// MARK: - Plugin Entry Point (Composition Root)

/// End-to-end-encryption layer for `meinchat` — Signal-protocol ratchet,
/// per-device fan-out, padded envelopes.
///
/// **Current state (2026-05-29).** Backend (S28.3a/3b) and the web client
/// are live. iOS exposes:
///
/// - The wire-contract HTTP services (`DeviceRegistryService`,
///   `PrekeyService`) — fully usable today.
/// - `EnvelopePacker` (CBOR pack/unpack) + `Padding` (256-byte pad/strip) +
///   `DowngradeGuard` (fail-closed protocol check) — pure-logic pieces,
///   covered by unit tests.
/// - `KeychainIdentityStore` — Keychain wrapper for the device-identity
///   private bytes, ready to hold whatever `LibSignalClient` serialises.
/// - `StubSecureMessaging` — registered under
///   `MeinChatSecureMessagingStoreID`. Throws `notReady` on every secure
///   send/decrypt. **Replace with the LibSignalClient-backed implementation
///   once that library is vendored.**
/// - Settings UI scaffolds: `PrekeyStatusRow`, `RevokeDeviceButton`,
///   `PairingSheet`. Live HTTP, no crypto.
///
/// The actual Signal-protocol session (encrypt/decrypt/X3DH/Double Ratchet)
/// requires `LibSignalClient` vendored under
/// `Sources/MeinChatPlusPlugin/Vendored/`. That's the next sprint —
/// when it lands, the only change here is to swap `StubSecureMessaging`
/// for the real implementation.
public final class MeinChatPlusPlugin: Plugin, @unchecked Sendable {
    nonisolated public init() {}

    // MARK: - Metadata

    public var metadata: PluginMetadata {
        PluginMetadata(
            name: "meinchat-plus",
            version: SemanticVersion(0, 2, 0),  // 0.x = pre-Signal
            description: "End-to-end encrypted messaging — Signal ratchet over meinchat.",
            author: "VBWD",
            keywords: ["chat", "messaging", "e2e", "signal", "meinchat"],
            dependencies: .list(["meinchat"]),
            translations: ["en": translations]
        )
    }

    // MARK: - Lifecycle

    @MainActor
    public func install(_ sdk: PlatformSDK) async throws {
        // HTTP wire services — usable today against S28.3b backend.
        let devices = DefaultDeviceRegistryService(api: sdk.api)
        let prekeys = DefaultPrekeyService(api: sdk.api)
        let identity = KeychainIdentityStore()

        // S67.2 — APNs token registration for the meinchat-plus app surface
        // (mirror of meinchat §3.5; auth-aware sink, ask-once permission
        // prompt after login, best-effort unregister on logout).
        let pushService = DefaultPushRegistrationService(api: sdk.api)
        let tokenSink = MeinChatPlusTokenSink(service: pushService)
        await sdk.notifications.registerSink(tokenSink)
        sdk.events.on(AppEvents.authLogin) { _ in
            Task { @MainActor in
                await MeinChatPlusNotificationPermissions.askOnce()
                await tokenSink.handleLogin()
            }
        }
        sdk.events.on(AppEvents.authLogout) { _ in
            Task { await tokenSink.handleLogout() }
        }

        // Cross-plugin secure-messaging contract: meinchat discovers our
        // service via `MeinChatSecureMessagingStoreID`. We register the
        // real Signal-backed implementation when LibSignalClient resolves,
        // and fall back to the fail-closed stub otherwise (so the build
        // never breaks if SPM hasn't fetched the dep yet).
        #if canImport(LibSignalClient)
        let signalStores = SignalProtocolStores(identity: identity)
        let pairing = SignalPairingService(
            stores: signalStores, devices: devices, prekeys: prekeys)
        let secure: MeinChatSecureMessaging = SignalSecureMessaging(
            api: sdk.api,
            stores: signalStores,
            devices: devices,
            pairing: pairing,
            currentUserId: { nil })  // TODO: surface from AuthSession
        try sdk.createStore(MeinChatSecureMessagingStoreID.value, secure as AnyObject)
        #else
        let secure: MeinChatSecureMessaging = StubSecureMessaging(identity: identity)
        try sdk.createStore(MeinChatSecureMessagingStoreID.value, secure as AnyObject)
        #endif

        // Settings registries (Profile* convention — meinchat plugin already
        // owns its `ProfileMeinChat*` slots; ours don't collide).
        sdk.addComponent("ProfileMeinChatPlusPrekeyStatus") { @MainActor in
            AnyView(PrekeyStatusRow(prekeys: prekeys, identity: identity))
        }
        sdk.addComponent("ProfileMeinChatPlusRevoke") { @MainActor in
            // Local-device id is populated at pairing time; until paired
            // the button is disabled (handled inside the view).
            AnyView(RevokeDeviceButton(deviceRegistry: devices,
                                       identity: identity,
                                       localDeviceId: nil))
        }
        sdk.addComponent("ProfileMeinChatPlusPair") { @MainActor in
            #if canImport(LibSignalClient)
            // Real pairing flow: PairingSheet's "Continue" tap dispatches
            // through SignalPairingService to mint identity + signed +
            // 100 one-time prekeys, then uploads them.
            let signalStores = SignalProtocolStores(identity: identity)
            let pairing = SignalPairingService(
                stores: signalStores, devices: devices, prekeys: prekeys)
            return AnyView(PairingSheet { mode, _ in
                let label = "iPhone (\(mode))"
                _ = try? await pairing.pair(label: label)
            })
            #else
            return AnyView(PairingSheet { _, _ in })  // no-op without crypto
            #endif
        }

        sdk.addTranslations("en", translations)
    }

    public func activate() async throws {}
    public func deactivate() async throws {}
    public func uninstall() async throws {}

    // MARK: - Translations

    private var translations: [String: String] {
        [
            "meinchat_plus.title": "Secure Chat",
            "meinchat_plus.status.unpaired": "Secure chat not paired",
            "meinchat_plus.status.ready": "Secure chat ready",
            "meinchat_plus.action.pair": "Pair this device",
            "meinchat_plus.action.revoke": "Revoke this device",
            "meinchat_plus.downgrade.title": "Secure mode unavailable",
            "meinchat_plus.downgrade.body": "The peer does not have a paired device. Conversation cannot be encrypted end-to-end.",
            "meinchat_plus.composer.peer_not_paired": "Peer can't receive secure messages yet.",
            "meinchat_plus.composer.local_not_paired": "Pair this device first to send secure messages.",
        ]
    }
}

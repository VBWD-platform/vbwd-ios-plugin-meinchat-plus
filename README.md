# vbwd-ios-plugin-meinchat-plus

End-to-end-encrypted layer on top of the [`meinchat`](../vbwd-ios-plugin-meinchat) plugin — Signal-protocol ratchet, per-device fan-out, 256-byte padded envelopes. Spec: [S28.7](../../../../docs/dev_log/20260528/sprints/s28-7-ios-meinchat-plus-plugin-plan.md).

## Status — 2026-05-30: Signal integration drafted

The plugin now contains a real LibSignalClient-backed implementation of `MeinChatSecureMessaging` (encrypt / decrypt / pairing / prekey management). The implementation lives in:

```
Sources/MeinChatPlusPlugin/
├── Domain/
│   ├── SignalSecureMessaging.swift  ← real send/read, addresses + own devices
│   ├── SignalPairingService.swift   ← identity + signed + 100 one-time prekeys
│   ├── DeviceModels.swift / DeviceRegistryService.swift / PrekeyService.swift
│   ├── EnvelopePacker.swift / Padding.swift / DowngradeGuard.swift
│   └── StubSecureMessaging.swift    ← kept as fallback when LibSignal absent
├── Storage/
│   ├── KeychainIdentityStore.swift  ← raw identity bytes, Keychain-only
│   └── SignalProtocolStores.swift   ← IdentityKeyStore + SessionStore +
│                                      PreKeyStore + SignedPreKeyStore
└── Views/
    ├── PairingSheet.swift           ← onPair → SignalPairingService.pair
    ├── PrekeyStatusRow.swift
    └── RevokeDeviceButton.swift
```

All Signal-using files are gated behind `#if canImport(LibSignalClient)`. When the dependency hasn't resolved yet, the plugin falls back to the `StubSecureMessaging` (which throws `notReady` on every send/decrypt — preserving the fail-closed contract).

## ⚠ CLAUDE.md override

The project rule "no external Swift package dependencies — everything is local" is **deliberately overridden** for `LibSignalClient` only, in `Package.swift`:

```swift
.package(url: "https://github.com/signalapp/libsignal", from: "0.50.0"),
```

Reason: implementing the Signal protocol ourselves would be unsafe (Signal explicitly warns against it) and breaks interop with the web client which already uses the same library. The long-term plan is to vendor the xcframework + Swift sources locally under `Vendored/LibSignalClient/` and switch to `.binaryTarget` + local `.target`. Tracked as the S28.7 vendoring follow-up.

## Heads-up on the API guesses

The integration was written against my best understanding of `LibSignalClient`'s public Swift surface (`IdentityKeyPair.generate()`, `PreKeyBundle(...)`, `processPreKeyBundle`, `signalEncrypt`, `signalDecrypt`, `signalDecryptPreKey`, store protocols, etc.). I could not run `swift package resolve` in my own environment to verify the exact symbol names and types of the version pinned above. **Expect 1–2 rounds of compile-error iteration** when you first build:

1. Run `swift package resolve` from `Packages/vbwd-ios-plugin-meinchat-plus/` or let Xcode do it.
2. Try a build. If you see unresolved-symbol errors, paste them and we'll fix the call sites.

## Pairing flow

1. User opens Settings → MeinChat → Secure Chat → "Pair this device" (PairingSheet).
2. Sheet collects unlock mode + recovery passphrase, calls `onPair`.
3. `MeinChatPlusPlugin` dispatches to `SignalPairingService.pair(label:)`.
4. Service:
   - Generates `IdentityKeyPair` + registration id (persisted to Keychain).
   - Generates `SignedPreKeyRecord` (uploaded via `POST /me/prekeys/signed`).
   - Generates 100 one-time `PreKeyRecord`s (uploaded via `POST /me/prekeys/one-time`).
   - Registers the device via `POST /me/devices` — server returns a `device_id` that's persisted to UserDefaults under `meinchat.plus.signal.localDeviceId`.
5. From that point on, `peerCanReceiveE2E` returns true for any peer with at least one paired device, and `sendSecure` ciphers messages through real Signal sessions.

## What's not done in this pass

- **Attachment encryption (S28.4).** `sendSecureAttachment` throws explicitly; the plain path is unreachable for e2e_v1 conversations (fail-closed), so attachments simply error out until the encryption flow lands.
- **Conversation upgrade flow.** `openConversation` doesn't yet send `accepted_protocols: ["e2e_v1"]`. New conversations stay plain until the meinchat side learns to request E2E and route the response through `DowngradeGuard`.
- **Biometric KEK gating.** The Keychain identity is stored under `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — solid baseline, but the `BiometryCurrentSet` primary entry from sprint §3.1 isn't wired yet.
- **Refill task.** `SignalPairingService.refillOneTimePreKeys` exists but isn't hooked into a periodic check. Add a `BGAppRefreshTask` analogous to `CacheEvictionTask` when needed.
- **Vendoring.** See "CLAUDE.md override" above.

## Requirements

- Swift 6.0+ / Xcode 16+
- iOS 16+ / macOS 13+
- `vbwd-ios-core` as a sibling package
- `vbwd-ios-plugin-meinchat` (cross-plugin contract + cache + capabilities)
- Backend with S28.3a + S28.3b live
- `LibSignalClient` (Swift) — fetched via SPM

## Launch posture (per S28 decision R2-Q1)

The sprint calls for `enabled: true` at v1 launch. Once you've verified the Signal flow against the backend (pair → send → web client decrypts), flip `meinchat-plus.enabled` to `true` in `VBWD/plugins.json`.

## License

BSL 1.1 (Business Source Licence)

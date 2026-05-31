// swift-tools-version:6.0
import PackageDescription

// ─────────────────────────────────────────────────────────────────────────────
// LibSignalClient integration NOTE:
// All Signal-protocol code (SignalSecureMessaging, SignalPairingService,
// SignalProtocolStores) is gated behind `#if canImport(LibSignalClient)`
// and currently compiles OUT — the plugin falls back to StubSecureMessaging
// (fail-closed: throws notReady on any e2e send/decrypt).
//
// To activate it:
//   1. Add a remote dep below (or vendor the xcframework + Swift sources
//      under `Vendored/LibSignalClient/` and add a `.binaryTarget`).
//   2. Add `.product(name: "LibSignalClient", package: "<pkg>")` to the
//      MeinChatPlusPlugin target's dependencies.
//   3. Resolve the graph; `canImport(LibSignalClient)` flips true and the
//      real send/read/pairing flows activate.
//
// We previously pinned `https://github.com/signalapp/libsignal` at
// `from: "0.50.0"` but that version pin failed to resolve in this project's
// Xcode and collapsed the whole SPM graph. Reinstate when we know the right
// version / URL / product name for the signal release we want.
// ─────────────────────────────────────────────────────────────────────────────

let package = Package(
    name: "VBWDMeinChatPlusPlugin",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "MeinChatPlusPlugin", targets: ["MeinChatPlusPlugin"]),
    ],
    dependencies: [
        .package(path: "../vbwd-ios-core"),
        .package(path: "../vbwd-ios-plugin-meinchat"),
    ],
    targets: [
        .target(
            name: "MeinChatPlusPlugin",
            dependencies: [
                .product(name: "VBWDCore", package: "vbwd-ios-core"),
                .product(name: "MeinChatPlugin", package: "vbwd-ios-plugin-meinchat"),
            ],
            path: "Sources/MeinChatPlusPlugin",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "MeinChatPlusPluginTests",
            dependencies: ["MeinChatPlusPlugin"],
            path: "Tests/MeinChatPlusPluginTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)

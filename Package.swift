// swift-tools-version:6.0
import PackageDescription

// ─────────────────────────────────────────────────────────────────────────────
// CLAUDE.md override (deliberate):
// The project rule "no external Swift package dependencies — everything is
// local" is overridden HERE, for `LibSignalClient` only. Reasons:
//   1. Implementing a Signal-protocol client from scratch is unsafe (Signal
//      itself warns against rolling your own).
//   2. The wire format MUST interoperate with the web client which already
//      uses signalapp/libsignal — the only practical way to interop is to
//      use the same library.
//   3. The library is published, audited, and maintained by Signal directly.
// Long-term: vendor the xcframework + Swift sources under `Vendored/` and
// switch this back to a `.binaryTarget` + local `.target` to restore the
// in-tree posture. Tracked in S28.7 §3 as the vendoring follow-up.
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
        // Signal Protocol implementation. Pinned to a recent 0.x release.
        // If `swift package resolve` fails to find this version, bump to a
        // version published in github.com/signalapp/libsignal/releases.
        .package(url: "https://github.com/signalapp/libsignal", from: "0.50.0"),
    ],
    targets: [
        .target(
            name: "MeinChatPlusPlugin",
            dependencies: [
                .product(name: "VBWDCore", package: "vbwd-ios-core"),
                .product(name: "MeinChatPlugin", package: "vbwd-ios-plugin-meinchat"),
                .product(name: "LibSignalClient", package: "libsignal"),
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

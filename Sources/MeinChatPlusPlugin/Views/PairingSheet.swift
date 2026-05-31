import SwiftUI
import VBWDCore

/// First-launch pairing UX (S28.7 §3.1). **Scaffold only** — the actual
/// `IdentityKeyPair` + signed/one-time prekey generation lives in
/// `LibSignalClient` which isn't vendored yet. This sheet collects the
/// user's choice (biometric primary vs. passphrase-only) + the recovery
/// passphrase and dispatches via the `onPair` callback. Once the Signal
/// layer lands, that callback runs the key-generation flow.
///
/// Until then, tapping "Continue" only persists the user's preference and
/// surfaces a "Secure messaging will be available in a future build" toast.
@MainActor
struct PairingSheet: View {
    /// Called when the user confirms pairing. `mode` is one of "biometric"
    /// or "passphrase"; `passphrase` is the recovery secret (never nil in
    /// passphrase-only mode, optional in biometric mode).
    let onPair: (_ mode: String, _ passphrase: String?) async -> Void
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var useBiometric: Bool = true
    @State private var passphrase: String = ""
    @State private var confirm: String = ""
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use Face ID / Touch ID", isOn: $useBiometric)
                        .accessibilityIdentifier("meinchat_plus_pair_biometric_toggle")
                } header: {
                    Text("Primary unlock")
                } footer: {
                    Text("Biometrics protect this device's secure keys. Disable to use a passphrase only.")
                }

                Section {
                    SecureField("Recovery passphrase", text: $passphrase)
                        .textContentType(.password)
                        .accessibilityIdentifier("meinchat_plus_pair_passphrase")
                    SecureField("Confirm passphrase", text: $confirm)
                        .textContentType(.password)
                        .accessibilityIdentifier("meinchat_plus_pair_passphrase_confirm")
                } header: {
                    Text("Recovery passphrase")
                } footer: {
                    Text(passphraseFooter)
                }

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(theme.destructive)
                }

                Section {
                    Button {
                        Task { await proceed() }
                    } label: {
                        HStack {
                            Text("Continue")
                            if isWorking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isWorking || !isValid)
                    .accessibilityIdentifier("meinchat_plus_pair_continue")
                }
            }
            .navigationTitle("Pair secure chat")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var passphraseFooter: String {
        useBiometric
            ? "Used only if biometrics are reset or the device is restored. Store somewhere safe."
            : "Required every time you send a secure message."
    }

    private var isValid: Bool {
        !passphrase.isEmpty && passphrase == confirm && passphrase.count >= 8
    }

    private func proceed() async {
        isWorking = true
        defer { isWorking = false }
        await onPair(useBiometric ? "biometric" : "passphrase", passphrase)
        dismiss()
    }
}

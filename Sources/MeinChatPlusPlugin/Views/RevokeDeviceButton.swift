import SwiftUI
import VBWDCore

/// Settings → MeinChat → Secure Chat → "Revoke this device" (S28.7 §3.5).
/// Confirms, then `DELETE /me/devices/<id>` + clears the local
/// `KeychainIdentityStore`. A re-pair from this device starts fresh keys.
@MainActor
struct RevokeDeviceButton: View {
    let deviceRegistry: DeviceRegistryServiceProtocol
    let identity: KeychainIdentityStore
    /// Local device id — populated at pairing time. nil ⇒ button disabled.
    let localDeviceId: String?
    @Environment(\.appTheme) private var theme
    @State private var showConfirm = false
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        Button(role: .destructive) {
            showConfirm = true
        } label: {
            HStack {
                Image(systemName: "xmark.shield.fill")
                Text("Revoke this device")
                if isWorking {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(localDeviceId == nil || isWorking)
        .accessibilityIdentifier("meinchat_plus_revoke_device")
        .confirmationDialog(
            "Revoke this device?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Revoke", role: .destructive) {
                Task { await revoke() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to pair again before sending secure messages. Existing E2E conversations will appear as 'cannot decrypt' until re-pair.")
        }
        if let error {
            Text(error)
                .font(.footnote)
                .foregroundStyle(theme.destructive)
        }
    }

    private func revoke() async {
        guard let id = localDeviceId else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await deviceRegistry.revokeDevice(id: id)
            try identity.clear()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

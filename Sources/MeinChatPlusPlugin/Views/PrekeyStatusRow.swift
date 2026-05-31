import SwiftUI
import VBWDCore

/// Settings → MeinChat → Secure Chat → "1 active device, 97 of 100 one-time
/// prekeys remaining" (S28.7 §3.5). Reads live values from the prekey
/// service; refreshes on `.onAppear` (no polling).
@MainActor
struct PrekeyStatusRow: View {
    let prekeys: PrekeyServiceProtocol
    let identity: KeychainIdentityStore
    @Environment(\.appTheme) private var theme
    @State private var status: PrekeyStatus?
    @State private var error: String?

    var body: some View {
        Section {
            HStack {
                Text("This device")
                Spacer()
                Text(identity.isPaired ? "Paired" : "Not paired")
                    .foregroundStyle(identity.isPaired ? theme.success : theme.textSecondary)
            }
            .accessibilityIdentifier("meinchat_plus_pairing_status")

            if let s = status {
                HStack {
                    Text("One-time prekeys")
                    Spacer()
                    Text("\(s.oneTimeRemaining) of \(s.oneTimeCapacity)")
                        .foregroundStyle(theme.textSecondary)
                }
                .accessibilityIdentifier("meinchat_plus_prekey_status")
                if let last = s.signedRotatedAt {
                    HStack {
                        Text("Signed prekey rotated")
                        Spacer()
                        Text(last)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } else if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(theme.destructive)
            } else {
                Text("Loading…")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
            }
        } header: {
            Text("Secure Chat")
        }
        .task { await refresh() }
    }

    private func refresh() async {
        do {
            status = try await prekeys.fetchStatus()
            self.error = nil
        } catch let e as APIError {
            self.error = e.message
            status = nil
        } catch let e {
            self.error = e.localizedDescription
            status = nil
        }
    }
}

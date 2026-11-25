import SwiftUI
import AIUsageDashboardCore

/// Paste-a-key sign-in under a live-quota switch (GitHub billing for Copilot, OpenCode Go).
/// The key goes straight into Tokei's own Keychain and is never shown again: after Save the
/// row only says Connected, with Remove to delete the Keychain item.
struct OfficialSignInRow: View {
    let signIn: OfficialSignIn
    /// The provider's latest warning for this sign-in (401, 403, no usage).
    let lastProblem: String?
    let onChange: () -> Void
    var store: any SecretStore = Keychain.shared

    private enum Status: Equatable {
        case checking
        case connected
        case notConnected
        case failed(String)
    }

    @State private var status: Status = .checking
    @State private var draft = ""
    @State private var busy = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.help(for: signIn))
                .font(.sans(size: 11))
                .foregroundColor(PadzyTheme.ink3)
                .fixedSize(horizontal: false, vertical: true)
            if status == .connected {
                connectedRow
            } else {
                entryRow
            }
            if let line = statusLine {
                Text(line)
                    .font(.sans(size: 11))
                    .foregroundColor(PadzyTheme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 28)
        .task { await refreshStatus() }
    }

    private var connectedRow: some View {
        HStack(spacing: 8) {
            Text("Connected")
                .font(.sans(size: 12, weight: .semibold))
                .foregroundColor(PadzyTheme.ink2)
            Text("key saved in Keychain")
                .font(.sans(size: 11))
                .foregroundColor(PadzyTheme.ink4)
            Spacer(minLength: 8)
            Button("Remove") { Task { await remove() } }
                .buttonStyle(.plain)
                .font(.sans(size: 11, weight: .semibold))
                .foregroundColor(PadzyTheme.ink)
                .disabled(busy)
                .accessibilityLabel("Remove \(Self.credentialName(for: signIn))")
        }
    }

    private var entryRow: some View {
        HStack(spacing: 8) {
            SecureField(Self.placeholder(for: signIn), text: $draft)
                .textFieldStyle(.plain)
                .font(.mono(size: 12))
                .foregroundColor(PadzyTheme.ink)
                .focused($fieldFocused)
                .onSubmit { Task { await save() } }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                        .fill(PadzyTheme.statusBar)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                        .stroke(fieldFocused ? PadzyTheme.accent : PadzyTheme.border2, lineWidth: 1)
                )
                .accessibilityLabel(Self.credentialName(for: signIn))
            Button("Save") { Task { await save() } }
                .buttonStyle(.plain)
                .font(.sans(size: 11, weight: .semibold))
                .foregroundColor(PadzyTheme.ink)
                .disabled(busy || Self.cleaned(draft) == nil)
        }
    }

    private var statusLine: String? {
        switch status {
        case .checking: return nil
        case .notConnected: return "Not connected"
        case .failed(let message): return message
        case .connected: return lastProblem
        }
    }

    // MARK: Actions

    private func refreshStatus() async {
        do {
            status = try await store.hasSecret(for: signIn.keychainAccount) ? .connected : .notConnected
        } catch {
            status = .failed("Couldn't check the Keychain. Try again.")
        }
    }

    private func save() async {
        guard let key = Self.cleaned(draft), !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await store.setSecret(key, for: signIn.keychainAccount)
            draft = ""
            status = .connected
            onChange()
        } catch {
            status = .failed("Couldn't save to the Keychain. Nothing was stored.")
        }
    }

    private func remove() async {
        busy = true
        defer { busy = false }
        do {
            try await store.removeSecret(for: signIn.keychainAccount)
            status = .notConnected
            onChange()
        } catch {
            status = .failed("Couldn't remove it from the Keychain. Try again.")
        }
    }

    // MARK: Copy

    /// A pasted key, trimmed; `nil` when empty or when it has spaces inside (a bad paste).
    static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        return trimmed
    }

    static func help(for signIn: OfficialSignIn) -> String {
        switch signIn {
        case .githubBilling:
            return "GitHub › Settings › Developer settings › Fine-grained tokens › Generate new token."
                + " Resource owner: your own account. Account permissions › Plan: Read-only."
                + " No repository access needed. Paste the token here."
                + " Seats paid by an organization or enterprise don't show here."
        case .opencodeGo:
            return "OpenCode Console › subscribe to Go if you haven't › copy your API key › paste it here."
        }
    }

    static func placeholder(for signIn: OfficialSignIn) -> String {
        switch signIn {
        case .githubBilling: return "GitHub fine-grained token"
        case .opencodeGo: return "OpenCode Go API key"
        }
    }

    static func credentialName(for signIn: OfficialSignIn) -> String {
        switch signIn {
        case .githubBilling: return "GitHub billing token"
        case .opencodeGo: return "OpenCode Go API key"
        }
    }
}

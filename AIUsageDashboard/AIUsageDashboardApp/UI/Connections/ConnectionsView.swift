import SwiftUI
import AIUsageDashboardCore

/// The Agents tab (WP-5 rebuild to the "Tokei Dashboard" mockup, outline
/// L220-268): one management card per connected agent, plus the honest,
/// local-first framing and the privacy note that anchors the app's whole pitch.
///
/// Every detected agent appears here — including hidden ones (dimmed, so they can
/// be un-hidden) — ordered by the canonical provider order for stability. Each
/// card owns its own visibility, rescan, and live-quota bindings (`ConnectionRow`);
/// this view only lays them out and carries the framing copy.
struct ConnectionsView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel
    /// Opens the shell's Add-agent drawer (overlaid on the whole window).
    var onAddAgent: () -> Void = {}

    /// Every provider that produced a snapshot this run, in canonical order.
    /// Includes hidden providers so the Show toggle can bring them back.
    private var agents: [ProviderID] {
        ProviderID.allCases.filter { viewModel.snapshot(for: $0) != nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                framing
                    .padding(.top, 12)

                if agents.isEmpty {
                    SurfaceStateView(
                        kind: .empty(
                            headline: "No agents detected",
                            hint: "Add a coding agent to manage it here. Tokei only ever reads local, read-only usage."
                        ),
                        compact: true
                    )
                    .padding(.top, 24)
                } else {
                    VStack(spacing: 10) {
                        ForEach(agents, id: \.self) { ConnectionRow(providerID: $0) }
                    }
                    .padding(.top, 22)
                }

                privacyNote
                    .padding(.top, 22)
            }
            .padding(.horizontal, 28)
            .padding(.top, 34)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PadzyTheme.ground)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            SectionLabel("Connected agents")
            AddAgentButton { onAddAgent() }
                .fixedSize()
        }
    }

    private var framing: some View {
        Text("Everything Tokei reads is local and read-only. Turn on live quota for agents that expose an online limit; toggle Show to include an agent in your totals.")
            .font(.sans(size: 13.5))
            .foregroundColor(PadzyTheme.ink3)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 580, alignment: .leading)
    }

    private var privacyNote: some View {
        Text("Live quota uses read-only credentials already on this Mac. Tokei never sends your prompts, code, or file contents anywhere.")
            .font(.mono(size: 11))
            .foregroundColor(PadzyTheme.ink5)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 580, alignment: .leading)
    }
}

// MARK: - Preview

@MainActor
private func mockViewModel(_ snapshots: [ProviderSnapshot]) -> DashboardViewModel {
    let vm = DashboardViewModel()
    vm.snapshots = snapshots
    return vm
}

@MainActor
private func mockSnapshot(_ id: ProviderID, name: String, today: TokenUsage = .unavailable) -> ProviderSnapshot {
    ProviderSnapshot(
        providerID: id,
        displayName: name,
        authStatus: .authenticated,
        quotaWindows: [],
        todayUsage: today,
        weekUsage: .unavailable,
        warnings: []
    )
}

#Preview("Agents") {
    ConnectionsView()
        .environmentObject(mockViewModel([
            mockSnapshot(.claudeCode, name: "Claude Code",
                         today: TokenUsage(inputTokens: 82_000_000, confidence: .exact)),
            mockSnapshot(.codex, name: "Codex",
                         today: TokenUsage(inputTokens: 8_000_000, confidence: .localParsed)),
            mockSnapshot(.cursor, name: "Cursor"),
            mockSnapshot(.antigravity, name: "Antigravity"),
        ]))
        .frame(width: 720, height: 620)
        .background(PadzyTheme.ground)
}

#Preview("Agents · narrow 640") {
    ConnectionsView()
        .environmentObject(mockViewModel([
            mockSnapshot(.claudeCode, name: "Claude Code",
                         today: TokenUsage(inputTokens: 82_000_000, confidence: .exact)),
            mockSnapshot(.cursor, name: "Cursor"),
        ]))
        .frame(width: 410, height: 620)
        .background(PadzyTheme.ground)
}

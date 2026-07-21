import SwiftUI
import AIUsageDashboardCore

/// One agent's management card on the Agents tab (WP-5 rebuild to the "Tokei
/// Dashboard" mockup, outline L235-266). Everything on the card is bound to real
/// state — no mock toggles:
///
/// - **Show** writes `ProviderVisibility` (include/exclude from every total). The
///   card dims when hidden, matching the mockup's opacity cue.
/// - **Watching / Rescan** reflects that Tokei watches every detected agent's
///   local logs; Rescan re-reads them (`viewModel.refresh()`). There is no
///   per-agent "pause", so the dot is an honest status indicator, not a fake
///   toggle.
/// - **Live quota** only appears for the three providers that actually expose an
///   online connector (`ProviderOverviewRow.connectableProviders`); its switch is
///   the same `@AppStorage` flag the connector reads at fetch time, and the OFF /
///   CONNECTING / LIVE state is derived from whether a live window has landed.
///   Local-only agents read "LOCAL LOGS ONLY" instead of a dead toggle.
///
/// The one place anything leaves the Mac — Cursor's authenticated request — keeps
/// its explicit disclosure line; the general privacy note lives in the footer.
struct ConnectionRow: View {
    let providerID: ProviderID

    @EnvironmentObject private var viewModel: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Include-in-totals flag, mirrored straight from `ProviderVisibility`'s key so
    /// flipping Show here updates every surface that filters by visibility.
    @AppStorage private var hiddenFlag: Bool
    /// The connector's live-quota opt-in (same key the fetch path reads). A sentinel
    /// key keeps `@AppStorage` valid for local-only providers; it always reads false.
    @AppStorage private var liveEnabled: Bool
    /// Transient: a Rescan is in flight (re-reading local logs).
    @State private var rescanning = false

    init(providerID: ProviderID) {
        self.providerID = providerID
        _hiddenFlag = AppStorage(wrappedValue: false, ProviderVisibility.key(for: providerID))
        _liveEnabled = AppStorage(
            wrappedValue: false,
            ProviderOverviewRow.liveEnabledKey(for: providerID) ?? "connections.noLive.\(providerID.rawValue)"
        )
    }

    // MARK: Derived state

    private var snapshot: ProviderSnapshot? { viewModel.snapshot(for: providerID) }

    private var displayName: String {
        snapshot?.displayName
            ?? providerID.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var path: String {
        ProviderMetadata.localPaths(for: providerID).first ?? "—"
    }

    private var capability: ProviderCapabilityTier {
        ProviderCapabilityTier.classify(snapshot)
    }

    private var connectable: Bool {
        ProviderOverviewRow.connectableProviders.contains(providerID)
    }

    private var hasLiveData: Bool {
        viewModel.utilization.contains { $0.providerID == providerID }
    }

    private var show: Bool { !hiddenFlag }

    private var showBinding: Binding<Bool> {
        Binding(get: { !hiddenFlag }, set: { hiddenFlag = !$0 })
    }

    /// OFF → CONNECTING (enabled, first window not yet in) → LIVE. Local-only
    /// providers never reach this — they show "LOCAL LOGS ONLY".
    private enum LiveState { case off, connecting, live }
    private var liveState: LiveState {
        guard liveEnabled else { return .off }
        return hasLiveData ? .live : .connecting
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            identityRow
            HairlineDivider()
            controlRow
            if connectable {
                disclosure
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .background(PadzyTheme.window)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(PadzyTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .opacity(show ? 1 : 0.55)
        .animation(reduceMotion ? nil : PadzyMotion.quick, value: show)
    }

    // MARK: Identity row

    private var identityRow: some View {
        HStack(alignment: .center, spacing: 12) {
            ProviderBrandMark.tinted(providerID, size: 28)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 9) {
                    Text(displayName)
                        .font(.sans(size: 13.5, weight: .semibold))
                        .foregroundColor(PadzyTheme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    capabilityChip
                }
                Text(path)
                    .font(.mono(size: 10.5))
                    .foregroundColor(PadzyTheme.ink5)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Text("Show")
                    .font(.sans(size: 11))
                    .foregroundColor(PadzyTheme.ink5)
                Toggle("", isOn: showBinding)
                    .labelsHidden()
                    .toggleStyle(.padzy)
                    .accessibilityLabel("Show \(displayName) in totals")
            }
            .fixedSize()
        }
        .padding(16)
    }

    private var capabilityChip: some View {
        Text(capability.label)
            .font(.mono(size: 8.5))
            .tracking(8.5 * 0.08)
            .foregroundColor(PadzyTheme.ink3)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                    .stroke(PadzyTheme.border2, lineWidth: 1)
            )
            .fixedSize()
            .accessibilityLabel("Capability: \(capability.label)")
    }

    // MARK: Control row

    private var controlRow: some View {
        HStack(spacing: 12) {
            watchIndicator
            rescanButton
            Spacer(minLength: 8)
            liveQuotaControl
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Honest status, not a toggle: Tokei watches every detected agent's local logs.
    private var watchIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(snapshot == nil ? PadzyTheme.ink5 : PadzyTheme.good)
                .frame(width: 6, height: 6)
            Text(snapshot == nil ? "Not found" : "Watching")
                .font(.sans(size: 11))
                .foregroundColor(PadzyTheme.ink3)
        }
        .accessibilityElement(children: .combine)
    }

    private var rescanButton: some View {
        Button {
            guard !rescanning else { return }
            rescanning = true
            Task {
                await viewModel.refresh()
                rescanning = false
            }
        } label: {
            Text(rescanning ? "Rescanning…" : "Rescan")
                .font(.sans(size: 10.5))
                .foregroundColor(PadzyTheme.ink3)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                        .stroke(PadzyTheme.border2, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(rescanning)
        .accessibilityLabel("Rescan \(displayName)'s local logs")
    }

    @ViewBuilder
    private var liveQuotaControl: some View {
        if connectable {
            HStack(spacing: 8) {
                Circle()
                    .fill(liveDotColor)
                    .frame(width: 6, height: 6)
                Text("LIVE QUOTA · \(liveStateLabel)")
                    .font(.mono(size: 9.5))
                    .tracking(9.5 * 0.1)
                    .foregroundColor(liveDotColor)
                Toggle("", isOn: $liveEnabled)
                    .labelsHidden()
                    .toggleStyle(.padzy)
                    .onChange(of: liveEnabled) {
                        Task { await viewModel.refresh() }
                    }
                    .accessibilityLabel("Live quota for \(displayName)")
            }
            .fixedSize()
        } else {
            Text("LOCAL LOGS ONLY")
                .font(.mono(size: 9.5))
                .tracking(9.5 * 0.1)
                .foregroundColor(PadzyTheme.ink5)
        }
    }

    private var liveStateLabel: String {
        switch liveState {
        case .off: return "OFF"
        case .connecting: return "CONNECTING"
        case .live: return "LIVE"
        }
    }

    private var liveDotColor: Color {
        switch liveState {
        case .off: return PadzyTheme.ink5
        case .connecting: return PadzyTheme.warn
        case .live: return PadzyTheme.good
        }
    }

    // MARK: Disclosure (connectable only)

    private var disclosure: some View {
        Text(Self.liveDisclosure(for: providerID))
            .font(.sans(size: 11))
            .foregroundColor(PadzyTheme.ink5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Per-provider live-quota disclosure — the exact honesty the prior Connections
    /// list carried. Cursor is the one case that makes an outbound request; that is
    /// said plainly.
    static func liveDisclosure(for providerID: ProviderID) -> String {
        switch providerID {
        case .claudeCode:
            return "Reads your own Claude account. May break if Anthropic changes their API."
        case .cursor:
            return "Makes an authenticated request to Cursor's servers using your local session token to fetch real token and quota usage."
        case .antigravity:
            return "Reads live quota from the running Antigravity app on your Mac. No token is stored or sent anywhere."
        default:
            return ""
        }
    }
}

// MARK: - Previews

@MainActor
private func mockViewModel(_ snapshots: [ProviderSnapshot]) -> DashboardViewModel {
    let vm = DashboardViewModel()
    vm.snapshots = snapshots
    return vm
}

@MainActor
private func mockSnapshot(
    _ id: ProviderID,
    name: String,
    windows: [QuotaWindow] = [],
    today: TokenUsage = .unavailable
) -> ProviderSnapshot {
    ProviderSnapshot(
        providerID: id,
        displayName: name,
        authStatus: .authenticated,
        quotaWindows: windows,
        todayUsage: today,
        weekUsage: .unavailable,
        warnings: []
    )
}

#Preview("Agent cards") {
    VStack(spacing: 10) {
        ConnectionRow(providerID: .claudeCode)
        ConnectionRow(providerID: .codex)
        ConnectionRow(providerID: .cursor)
    }
    .padding(28)
    .frame(width: 640)
    .environmentObject(mockViewModel([
        mockSnapshot(.claudeCode, name: "Claude Code",
                     today: TokenUsage(inputTokens: 82_000_000, confidence: .exact)),
        mockSnapshot(.codex, name: "Codex",
                     today: TokenUsage(inputTokens: 8_000_000, confidence: .localParsed)),
        mockSnapshot(.cursor, name: "Cursor"),
    ]))
    .background(PadzyTheme.ground)
}

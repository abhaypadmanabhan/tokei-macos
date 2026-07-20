import SwiftUI
import AIUsageDashboardCore

/// Horizontal provider strip at the top of the dashboard — the replacement for
/// the sidebar's seven provider rows (LangSmith chip-row pattern).
///
/// A chip is identity + exactly ONE live number (`MaxxerMath.chipStat`), and the
/// trailing `+` opens the same Add Agent flow the sidebar header used. Clicking a
/// chip drills into that provider's detail; the strip stays put and marks the
/// active chip with the 2px accent tick, so the drill-in reads as a selection
/// rather than a trip to a different place.
///
/// Accent appears here for two states only: the active chip's tick, and a
/// provider at/over 90% of its tightest window (paired with `!!` so the warning
/// never rides on colour alone).
///
/// States: the whole strip collapses to a labelled `+ ADD AGENT` when nothing is
/// visible (never a blank rail); chips read `···` while the first sync is in
/// flight; and when a sync failed before any snapshot arrived, the strip leads
/// with an inline `!! SYNC FAILED` retry instead of a row of empty chips.
struct ProviderChipStrip: View {
    /// The drilled-into provider, or `nil` while a tab owns the content.
    let selected: ProviderID?
    let onSelect: (ProviderID) -> Void
    let onAddAgent: () -> Void
    let onRetry: () -> Void

    @EnvironmentObject private var viewModel: DashboardViewModel

    /// Provider visibility lives in `UserDefaults`, which publishes nothing
    /// SwiftUI tracks. Bumped on `didChangeNotification` so hiding an agent in
    /// Settings removes its chip immediately rather than one navigation late.
    @State private var storeRevision = 0

    private var visibleProviders: [ProviderID] {
        _ = storeRevision
        return ProviderID.allCases.filter { !ProviderVisibility.isHidden($0) }
    }

    /// A sync failed AND there is nothing to show — the only case where the strip
    /// itself owns the error rather than deferring to the pane below it.
    private var isBlockedByError: Bool {
        viewModel.errorMessage != nil && viewModel.snapshots.isEmpty
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                if isBlockedByError {
                    errorChip
                } else {
                    ForEach(visibleProviders, id: \.self) { providerID in
                        chip(providerID)
                    }
                }
                addChip(labelled: visibleProviders.isEmpty || isBlockedByError)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 44)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            storeRevision &+= 1
        }
        .accessibilityLabel("Agents")
    }

    // MARK: Chip

    private func chip(_ providerID: ProviderID) -> some View {
        let snapshot = viewModel.snapshot(for: providerID)
        let stat = MaxxerMath.chipStat(
            providerID: providerID,
            snapshot: snapshot,
            utilizations: viewModel.utilization,
            planLabel: snapshot.flatMap { ProviderMetadata.planText(from: $0.warnings) },
            isLoading: viewModel.isLoading
        )
        let isSelected = selected == providerID
        let isAvailable = viewModel.isAvailable(providerID)
        let name = snapshot?.displayName ?? providerID.rawValue.replacingOccurrences(of: "_", with: " ")

        return ProviderChip(
            providerID: providerID,
            name: name,
            stat: stat,
            isSelected: isSelected,
            isAvailable: isAvailable,
            action: { onSelect(providerID) }
        )
    }

    // MARK: `+`

    private func addChip(labelled: Bool) -> some View {
        Button(action: onAddAgent) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                if labelled {
                    Text("ADD AGENT")
                        .font(.mono(size: 11))
                }
            }
            .foregroundColor(PadzyTheme.accent)
            .padding(.horizontal, labelled ? 12 : 10)
            .padding(.vertical, 7)
            .overlay(
                RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                    .stroke(PadzyTheme.accent, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 8)
        .accessibilityLabel("Add a coding agent")
    }

    // MARK: Error

    /// Nothing synced and the sync failed — an actionable line instead of a rail
    /// of empty chips. The pane below still carries the full error detail.
    private var errorChip: some View {
        Button(action: onRetry) {
            HStack(spacing: 8) {
                Text("!!")
                    .font(.mono(size: 11))
                    .foregroundColor(PadzyTheme.accent)
                Text("SYNC FAILED — RETRY")
                    .font(.mono(size: 11))
                    .foregroundColor(PadzyTheme.ink)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlay(
                RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                    .stroke(PadzyTheme.muted.opacity(0.35), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sync failed. Retry")
    }
}

/// One provider chip. Split out so hover state is per-chip and the strip stays
/// a pure layout.
private struct ProviderChip: View {
    let providerID: ProviderID
    let name: String
    let stat: MaxxerMath.ChipStat
    let isSelected: Bool
    let isAvailable: Bool
    let action: () -> Void

    @State private var isHovered = false

    /// `≥ 90%` on the tightest window — the one ambient warning a chip carries.
    private var isCritical: Bool {
        if case let .utilization(percent) = stat {
            return ProviderOverviewRow.isCritical(percent)
        }
        return false
    }

    private var statText: String {
        switch stat {
        case let .tokens(tokens): return TokenFormatter.format(tokens)
        case let .utilization(percent): return "\(Int(round(percent)))%"
        case let .plan(plan): return plan.uppercased()
        case .syncing: return "···"
        case .none: return "—"
        }
    }

    private var statColor: Color {
        switch stat {
        case let .utilization(percent): return ProviderOverviewRow.thresholdColor(percent)
        case .tokens: return PadzyTheme.ink
        case .plan, .syncing, .none: return PadzyTheme.muted
        }
    }

    /// Spoken form — `···` and `—` are visual shorthand, not words.
    private var spokenStat: String {
        switch stat {
        case let .tokens(tokens): return "\(TokenFormatter.format(tokens)) tokens today"
        case let .utilization(percent): return "\(Int(round(percent))) percent of tightest limit used"
        case let .plan(plan): return "plan \(plan)"
        case .syncing: return "syncing"
        case .none: return "no data yet"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isAvailable {
                    ProviderBrandMark(providerID, size: 16)
                } else {
                    ProviderMark(providerID, size: 14, enabled: false)
                        .frame(width: 16, height: 16)
                }

                Text(name.uppercased())
                    .font(.display(size: 11, weight: .bold))
                    .foregroundColor(isAvailable ? PadzyTheme.ink : PadzyTheme.muted)
                    .lineLimit(1)

                HStack(spacing: 3) {
                    if isCritical {
                        Text("!!")
                            .font(.mono(size: 10))
                            .foregroundColor(PadzyTheme.accent)
                    }
                    Text(statText)
                        .font(.mono(size: 11))
                        .monospacedDigit()
                        .foregroundColor(statColor)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(chipBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isSelected ? PadzyTheme.accent : Color.clear)
                    .frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(name), \(spokenStat)")
        .accessibilityHint("Opens \(name) detail")
    }

    private var chipBackground: Color {
        if isSelected { return PadzyTheme.surface }
        return isHovered ? PadzyTheme.surface.opacity(0.5) : Color.clear
    }
}

// MARK: - Previews

@MainActor
private func chipPreviewModel(_ snapshots: [ProviderSnapshot], error: String? = nil, loading: Bool = false) -> DashboardViewModel {
    for id in ProviderID.allCases { ProviderVisibility.setHidden(false, for: id) }
    let vm = DashboardViewModel()
    vm.snapshots = snapshots
    vm.errorMessage = error
    vm.isLoading = loading
    return vm
}

@MainActor
private func chipSnapshot(_ id: ProviderID, _ name: String,
                          today: TokenUsage = .unavailable,
                          windows: [QuotaWindow] = [],
                          plan: String? = nil) -> ProviderSnapshot {
    ProviderSnapshot(
        providerID: id, displayName: name, authStatus: .authenticated,
        quotaWindows: windows, todayUsage: today, weekUsage: .unavailable,
        warnings: plan.map { [ProviderWarning(message: "Plan: \($0)", level: .info)] } ?? []
    )
}

#Preview("Chips · loaded") {
    VStack(spacing: 0) {
        ProviderChipStrip(selected: .claudeCode, onSelect: { _ in }, onAddAgent: {}, onRetry: {})
            .environmentObject(chipPreviewModel([
                chipSnapshot(.claudeCode, "Claude Code",
                             today: TokenUsage(inputTokens: 12_400_000, outputTokens: 1_900_000, confidence: .exact),
                             windows: [QuotaWindow(providerID: .claudeCode, type: .weekly, used: 94, limit: 100,
                                                   resetAt: Date().addingTimeInterval(86_400),
                                                   confidence: .providerReported, source: "preview")]),
                chipSnapshot(.cursor, "Cursor",
                             windows: [QuotaWindow(providerID: .cursor, type: .monthly, used: 93, limit: 100,
                                                   resetAt: Date().addingTimeInterval(86_400),
                                                   confidence: .providerReported, source: "preview")]),
                chipSnapshot(.codex, "Codex", plan: "Pro"),
            ]))
        HairlineDivider()
    }
    .frame(width: 900)
    .background(PadzyTheme.ground)
}

#Preview("Chips · empty canvas") {
    VStack(spacing: 0) {
        ProviderChipStrip(selected: nil, onSelect: { _ in }, onAddAgent: {}, onRetry: {})
            .environmentObject({
                let vm = chipPreviewModel([])
                for id in ProviderID.allCases { ProviderVisibility.setHidden(true, for: id) }
                return vm
            }())
        HairlineDivider()
    }
    .frame(width: 640)
    .background(PadzyTheme.ground)
}

#Preview("Chips · syncing") {
    VStack(spacing: 0) {
        ProviderChipStrip(selected: nil, onSelect: { _ in }, onAddAgent: {}, onRetry: {})
            .environmentObject(chipPreviewModel([], loading: true))
        HairlineDivider()
    }
    .frame(width: 640)
    .background(PadzyTheme.ground)
}

#Preview("Chips · sync failed") {
    VStack(spacing: 0) {
        ProviderChipStrip(selected: nil, onSelect: { _ in }, onAddAgent: {}, onRetry: {})
            .environmentObject(chipPreviewModel([], error: "Keychain access denied"))
        HairlineDivider()
    }
    .frame(width: 640)
    .background(PadzyTheme.ground)
}

import SwiftUI
import AIUsageDashboardCore

/// One glanceable line on the Overview home: a single provider reduced to its
/// **tightest** live-quota window (the reading closest to its ceiling). A live
/// row is itself a button that opens the provider's detail tab; a provider with
/// no computable live quota renders muted with a `Connect live quota →` action
/// that routes to the Connections screen.
///
/// Layout is fully flexible — the identity labels truncate and the fill bar
/// flexes so the row never crops down to the 640pt minimum window width.
struct ProviderOverviewRow: View {
    let providerID: ProviderID
    let displayName: String
    let plan: String?
    /// The provider's tightest window, or `nil` when it exposes no live quota.
    let tightest: Utilization?
    let onOpen: () -> Void
    let onConnect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Providers that have a live-quota connector on the Connections screen. Only
    /// these get the "Connect live quota →" affordance when unavailable; the rest
    /// (codex, cline) surface via local logs only and show a muted state instead.
    static let connectableProviders: Set<ProviderID> = [.claudeCode, .cursor, .antigravity]

    init(
        providerID: ProviderID,
        displayName: String,
        plan: String?,
        tightest: Utilization?,
        onOpen: @escaping () -> Void,
        onConnect: @escaping () -> Void
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.plan = plan
        self.tightest = tightest
        self.onOpen = onOpen
        self.onConnect = onConnect
    }

    // MARK: Threshold color (shared quota semantics — reused by Overview)

    /// Bar + value color by how close the window is to its ceiling.
    /// `≥ 90` critical (accent) · `≥ 70` warning · else nominal.
    static func thresholdColor(_ usedPercent: Double) -> Color {
        if usedPercent >= 90 { return PadzyTheme.accent }
        if usedPercent >= 70 { return Color(hex: "E8A23D") }
        return Color(hex: "3DBE8B")
    }

    var body: some View {
        if let tightest {
            Button(action: onOpen) {
                liveRow(tightest)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(accessibilityLabel(tightest))
            .accessibilityHint("Opens \(displayName) detail")
        } else {
            unavailableRow
        }
    }

    // MARK: Live

    private func liveRow(_ util: Utilization) -> some View {
        let percent = Int(round(util.usedPercent))
        let color = Self.thresholdColor(util.usedPercent)

        return HStack(spacing: 14) {
            ProviderMark(providerID, size: 20, enabled: true)

            identity(windowLabel: windowLabel(util.window))
                .layoutPriority(1)

            fillBar(percent: util.usedPercent, color: color)
                .frame(minWidth: 48, maxWidth: .infinity)

            Text("\(percent)%")
                .font(.mono(size: 13))
                .monospacedDigit()
                .foregroundColor(color)
                .frame(minWidth: 44, alignment: .trailing)

            countdown(util.resetAt)
                .frame(width: 78, alignment: .trailing)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }

    // MARK: Unavailable

    private var unavailableRow: some View {
        HStack(spacing: 14) {
            ProviderMark(providerID, size: 20, enabled: false)

            identity(windowLabel: nil)
                .layoutPriority(1)

            Spacer(minLength: 8)

            if Self.connectableProviders.contains(providerID) {
                Button(action: onConnect) {
                    Text("Connect live quota →")
                        .font(.mono(size: 11))
                        .foregroundColor(PadzyTheme.accent)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Connections")
            } else {
                // codex / cline expose no online connector — honest muted state, no
                // dead-end Connect button routing to a screen without their row.
                Text("LOCAL LOGS ONLY")
                    .font(.mono(size: 11))
                    .foregroundColor(PadzyTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }

    // MARK: Pieces

    /// Provider name + optional plan, above a window-type (or blank) label.
    /// Both lines truncate so the row never forces the window wider.
    private func identity(windowLabel: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(displayName)
                    .font(.display(size: 14, weight: .bold))
                    .foregroundColor(tightest == nil ? PadzyTheme.muted : PadzyTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let plan, !plan.isEmpty {
                    Text(plan.uppercased())
                        .font(.mono(size: 10))
                        .foregroundColor(PadzyTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Text(windowLabel ?? "NO LIVE QUOTA")
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.muted)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: 220, alignment: .leading)
    }

    /// 4pt-tall hairline gauge: full-width muted track with a threshold-colored
    /// fill proportional to used percent. Radius ≤ 2, no shadow/gradient.
    private func fillBar(percent: Double, color: Color) -> some View {
        let clamped = max(0, min(100, percent))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(PadzyTheme.muted.opacity(0.3))
                    .frame(height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(clamped / 100.0), height: 4)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 4)
    }

    /// Reset countdown. Ticks once a second normally; a static snapshot under
    /// Reduce Motion so the number never animates.
    @ViewBuilder
    private func countdown(_ resetAt: Date?) -> some View {
        if let resetAt {
            if reduceMotion {
                countdownLabel(Self.format(until: resetAt, now: Date()))
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    countdownLabel(Self.format(until: resetAt, now: context.date))
                }
            }
        } else {
            countdownLabel("—")
        }
    }

    private func countdownLabel(_ text: String) -> some View {
        Text(text)
            .font(.mono(size: 10))
            .monospacedDigit()
            .foregroundColor(PadzyTheme.muted)
            .lineLimit(1)
    }

    // MARK: Formatting

    private func windowLabel(_ type: QuotaWindowType) -> String {
        switch type {
        case .fiveHour: return "5-HOUR"
        case .perModel: return "PER MODEL"
        default: return type.rawValue.uppercased()
        }
    }

    /// Days-out windows read as "4d 9h"; nearer ones as "HH:MM:SS" / "MM:SS".
    static func format(until date: Date, now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "NOW" }
        let totalSeconds = Int(interval)
        let totalHours = totalSeconds / 3600
        if totalHours >= 24 {
            return "\(totalHours / 24)d \(totalHours % 24)h"
        }
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if totalHours > 0 {
            return String(format: "%02d:%02d:%02d", totalHours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func accessibilityLabel(_ util: Utilization) -> String {
        let pct = Int(round(util.usedPercent))
        let planPart = plan.map { ", \($0)" } ?? ""
        return "\(displayName)\(planPart), \(windowLabel(util.window)) \(pct) percent used"
    }
}

// MARK: - Previews

#Preview("States") {
    let now = Date()
    return VStack(spacing: 0) {
        HairlineDivider()
        ProviderOverviewRow(
            providerID: .claudeCode, displayName: "Claude Code", plan: "Max · yearly",
            tightest: Utilization(providerID: .claudeCode, window: .weekly, usedPercent: 95,
                                  resetAt: now.addingTimeInterval(4 * 86_400 + 9 * 3600),
                                  plan: "Max · yearly", confidence: .providerReported),
            onOpen: {}, onConnect: {}
        )
        HairlineDivider()
        ProviderOverviewRow(
            providerID: .cursor, displayName: "Cursor", plan: "Pro",
            tightest: Utilization(providerID: .cursor, window: .monthly, usedPercent: 78,
                                  resetAt: now.addingTimeInterval(11 * 3600 + 42 * 60),
                                  plan: "Pro", confidence: .providerReported),
            onOpen: {}, onConnect: {}
        )
        HairlineDivider()
        ProviderOverviewRow(
            providerID: .antigravity, displayName: "Antigravity", plan: nil,
            tightest: Utilization(providerID: .antigravity, window: .fiveHour, usedPercent: 32,
                                  resetAt: now.addingTimeInterval(3 * 3600 + 12 * 60 + 33),
                                  plan: nil, confidence: .providerReported),
            onOpen: {}, onConnect: {}
        )
        HairlineDivider()
        ProviderOverviewRow(
            providerID: .codex, displayName: "Codex", plan: nil,
            tightest: nil, onOpen: {}, onConnect: {}
        )
        HairlineDivider()
    }
    .frame(width: 640)
    .background(PadzyTheme.ground)
}

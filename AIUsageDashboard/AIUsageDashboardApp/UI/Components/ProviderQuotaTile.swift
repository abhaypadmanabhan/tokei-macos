import SwiftUI
import AIUsageDashboardCore

/// Quota-state color, distinct from `PadzyTheme.accent`. The tile's bar fill is a
/// state signal, not decoration, and the acceptance criteria mandate a three-tier
/// read (critical / warning / nominal) a single accent hue can't carry — reserving
/// this alongside the one-accent rule rather than replacing it.
private enum QuotaStateColor {
    static let critical = Color(hex: "FF3B70")
    static let warning = Color(hex: "E8A23D")
    static let nominal = Color(hex: "3DBE8B")

    static func forUsedPercent(_ percent: Double) -> Color {
        if percent >= 90 { return critical }
        if percent >= 70 { return warning }
        return nominal
    }
}

/// One provider's quota tile — plan label + one live bar per quota window. Reads
/// only `Utilization` (the Wave-1 spine's mapped `[QuotaWindow] -> usedPercent`
/// output via `DashboardViewModel.utilization`); it never recomputes a percentage
/// from raw `used`/`limit`, so the tile and the spine can never disagree.
struct ProviderQuotaTile: View {
    let providerID: ProviderID
    let displayName: String
    let plan: String?
    /// This provider's windows, already filtered to `providerID` by the caller.
    let windows: [Utilization]
    let isSelected: Bool
    /// True while the first sync is still in flight and no snapshot exists yet —
    /// distinct from "synced, but this provider reports nothing."
    let isLoading: Bool

    private static let windowOrder: [QuotaWindowType] = [
        .session, .fiveHour, .daily, .weekly, .monthly, .perModel, .credits, .lifetime,
    ]

    private var orderedWindows: [Utilization] {
        windows.sorted {
            (Self.windowOrder.firstIndex(of: $0.window) ?? Int.max)
                < (Self.windowOrder.firstIndex(of: $1.window) ?? Int.max)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(isSelected ? PadzyTheme.accent : Color.clear)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 10) {
                header
                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(PadzyTheme.surface)
        .border(PadzyTheme.muted.opacity(0.3), width: 1)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(displayName.uppercased())
                .font(.display(size: 13, weight: .bold))
                .foregroundColor(PadzyTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let plan {
                Text(plan.uppercased())
                    .font(.mono(size: 10))
                    .foregroundColor(PadzyTheme.muted)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            SurfaceStateView(kind: .loading(message: "Reading quota"), compact: true)
        } else if orderedWindows.isEmpty {
            // Honest empty state for a `.unavailable` provider — never a fake bar.
            SurfaceStateView(
                kind: .empty(headline: "Quota unavailable", hint: "No live window reported locally."),
                compact: true
            )
        } else {
            VStack(spacing: 10) {
                ForEach(orderedWindows) { window in
                    QuotaWindowBar(utilization: window)
                }
            }
        }
    }
}

/// One window's row inside a `ProviderQuotaTile`: label + used% bar + live
/// countdown to `resetAt`.
private struct QuotaWindowBar: View {
    let utilization: Utilization

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clampedPercent: Double {
        max(0, min(100, utilization.usedPercent))
    }

    private var color: Color {
        QuotaStateColor.forUsedPercent(clampedPercent)
    }

    private var windowLabel: String {
        switch utilization.window {
        case .fiveHour: return "5-HOUR"
        case .perModel: return "PER MODEL"
        default: return utilization.window.rawValue.uppercased()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(windowLabel)
                    .font(.mono(size: 11))
                    .foregroundColor(PadzyTheme.muted)
                ConfidenceBadge(confidence: utilization.confidence)
                Spacer(minLength: 8)
                Text("\(Int(round(clampedPercent)))%")
                    .font(.mono(size: 11))
                    .foregroundColor(color)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(PadzyTheme.muted.opacity(0.3))
                        .frame(height: 1)
                    Rectangle()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(clampedPercent / 100.0), height: 1)
                }
            }
            .frame(height: 1)

            if let resetAt = utilization.resetAt {
                countdown(to: resetAt)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Ticks every second unless Reduce Motion is on, in which case the countdown
    /// renders once from the view's construction time and does not animate.
    @ViewBuilder
    private func countdown(to resetAt: Date) -> some View {
        if reduceMotion {
            Text("RESETS \(formatCountdown(resetAt, now: Date()))")
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.muted)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("RESETS \(formatCountdown(resetAt, now: context.date))")
                    .font(.mono(size: 10))
                    .foregroundColor(PadzyTheme.muted)
            }
        }
    }

    private func formatCountdown(_ resetAt: Date, now: Date) -> String {
        let interval = resetAt.timeIntervalSince(now)
        guard interval > 0 else { return "now" }
        let totalHours = Int(interval) / 3600
        if totalHours >= 24 {
            let days = totalHours / 24
            let hours = totalHours % 24
            return "\(days)d \(hours)h"
        }
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if totalHours > 0 {
            return String(format: "%02d:%02d:%02d", totalHours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var accessibilityLabel: String {
        let resets: String
        if let resetAt = utilization.resetAt {
            let diff = resetAt.timeIntervalSince(Date())
            if diff <= 0 {
                resets = ", resets now"
            } else {
                let hours = Int(diff) / 3600
                let minutes = (Int(diff) % 3600) / 60
                resets = hours > 0
                    ? ", resets in \(hours) hour\(hours == 1 ? "" : "s")"
                    : ", resets in \(minutes) minute\(minutes == 1 ? "" : "s")"
            }
        } else {
            resets = ""
        }
        return "\(windowLabel) window \(Int(round(clampedPercent))) percent used\(resets)"
    }
}

// MARK: - Previews

#Preview("Populated") {
    ProviderQuotaTile(
        providerID: .cursor,
        displayName: "Cursor",
        plan: "Pro · yearly",
        windows: [
            Utilization(providerID: .cursor, window: .fiveHour, usedPercent: 42,
                        resetAt: Date().addingTimeInterval(3 * 3600 + 900), plan: "Pro · yearly",
                        confidence: .providerReported),
            Utilization(providerID: .cursor, window: .weekly, usedPercent: 78,
                        resetAt: Date().addingTimeInterval(2 * 86400 + 3600), plan: "Pro · yearly",
                        confidence: .providerReported),
            Utilization(providerID: .cursor, window: .monthly, usedPercent: 96,
                        resetAt: Date().addingTimeInterval(9 * 86400), plan: "Pro · yearly",
                        confidence: .estimated),
        ],
        isSelected: true,
        isLoading: false
    )
    .frame(width: 300)
    .padding(20)
    .background(PadzyTheme.ground)
}

#Preview("Unavailable") {
    ProviderQuotaTile(
        providerID: .claudeCode,
        displayName: "Claude Code",
        plan: nil,
        windows: [],
        isSelected: false,
        isLoading: false
    )
    .frame(width: 300)
    .padding(20)
    .background(PadzyTheme.ground)
}

#Preview("Loading") {
    ProviderQuotaTile(
        providerID: .antigravity,
        displayName: "Antigravity",
        plan: nil,
        windows: [],
        isSelected: false,
        isLoading: true
    )
    .frame(width: 300)
    .padding(20)
    .background(PadzyTheme.ground)
}

import SwiftUI
import AIUsageDashboardCore

/// Ambient quota strip between the tab bar and the content. It surfaces the single
/// tightest live window across every connected provider — the number that actually
/// constrains you right now — as one quiet, tappable line. Tapping drills into that
/// provider's detail.
///
/// The shell (`DashboardView`) owns the visibility gate: it only mounts this when a
/// live window exists and the pane is a non-Agents tab, so the banner itself always
/// has a window to render and never has to decide whether to appear.
///
/// Colour follows pressure, never chrome: the row tints faintly at ≥60% / ≥90% and
/// the dot takes `PadzyTheme.quotaColor`. Accent only ever shows here as the ≥90%
/// critical tint, paired with the number — never as decoration.
struct PressureBanner: View {
    /// The tightest window to surface (already selected by the shell via
    /// `MaxxerMath.tightestWindow(in:)`).
    let utilization: Utilization
    /// Resolved, human-readable provider name (the shell has the snapshot).
    let providerDisplayName: String
    /// Drill into the given provider's detail.
    let onTap: (ProviderID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pct: Int { Int(round(max(0, min(100, utilization.usedPercent)))) }

    private var tint: Color {
        if pct >= 90 { return PadzyTheme.accent.opacity(0.06) }
        if pct >= 60 { return PadzyTheme.warn.opacity(0.06) }
        return .clear
    }

    private var headline: String {
        "\(providerDisplayName) — \(windowLabel(utilization.window).lowercased()) at \(pct)%"
    }

    private var meta: String {
        (resetString ?? "your tightest window") + " \u{203A}"
    }

    var body: some View {
        Button(action: { onTap(utilization.providerID) }) {
            HStack(spacing: 11) {
                Circle()
                    .fill(PadzyTheme.quotaColor(Double(pct)))
                    .frame(width: 6, height: 6)

                Text(headline)
                    .font(.sans(size: 13))
                    .foregroundColor(PadzyTheme.ink2)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 12)

                Text(meta)
                    .font(.mono(size: 11))
                    .foregroundColor(PadzyTheme.ink4)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint)
            .overlay(alignment: .top) { HairlineDivider() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(providerDisplayName), \(windowLabel(utilization.window).lowercased()) at \(pct) percent")
        .accessibilityHint("Opens \(providerDisplayName) detail")
    }

    // MARK: Formatting

    /// A concise human label for a quota window type, used in the ambient line.
    private func windowLabel(_ window: QuotaWindowType) -> String {
        switch window {
        case .session: return "session"
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .fiveHour: return "5-hour"
        case .monthly: return "monthly"
        case .credits: return "credits"
        case .perModel: return "per-model"
        case .lifetime: return "lifetime"
        }
    }

    /// "resets in 3h 20m" style, or `nil` when the window reports no reset instant
    /// (the shell then falls back to "your tightest window").
    private var resetString: String? {
        guard let resetAt = utilization.resetAt else { return nil }
        let remaining = resetAt.timeIntervalSince(Date())
        guard remaining > 0 else { return "resets now" }
        let totalMinutes = Int(remaining) / 60
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "resets in \(days)d \(hours)h" }
        if hours > 0 { return "resets in \(hours)h \(minutes)m" }
        return "resets in \(minutes)m"
    }
}

// MARK: - Previews

#Preview("Pressure · critical") {
    VStack(spacing: 0) {
        PressureBanner(
            utilization: Utilization(
                providerID: .claudeCode, window: .weekly, usedPercent: 94,
                resetAt: Date().addingTimeInterval(4 * 86_400 + 6 * 3_600),
                confidence: .providerReported
            ),
            providerDisplayName: "Claude Code",
            onTap: { _ in }
        )
        HairlineDivider()
    }
    .frame(width: 900)
    .background(PadzyTheme.ground)
}

#Preview("Pressure · warn, no reset") {
    VStack(spacing: 0) {
        PressureBanner(
            utilization: Utilization(
                providerID: .antigravity, window: .fiveHour, usedPercent: 71,
                resetAt: nil, confidence: .providerReported
            ),
            providerDisplayName: "Antigravity",
            onTap: { _ in }
        )
        HairlineDivider()
    }
    .frame(width: 900)
    .background(PadzyTheme.ground)
}

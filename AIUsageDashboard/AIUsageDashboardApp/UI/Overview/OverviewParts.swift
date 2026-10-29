import SwiftUI
import AIUsageDashboardCore

/// Which lens the Overview hero + main chart present. `usage` = tokens over time;
/// `cost` = what those tokens would cost at public API rates; `quota` = how close each
/// plan is to its ceiling. Local pane state — never Core.
enum OverviewMetric: String, CaseIterable, Identifiable {
    case usage
    case cost
    case quota

    var id: String { rawValue }
    var title: String {
        switch self {
        case .usage: return "Usage"
        case .cost: return "Cost"
        case .quota: return "Quota"
        }
    }
}

/// Two flat text buttons (mockup): the active one takes `ink` plus a 2px accent
/// bottom tick (Padzy Invariant 4), the inactive one stays `ink5`. Settle animated,
/// reduce-motion safe (gated by the caller passing a nil animation is unnecessary —
/// the tick just snaps).
struct OverviewMetricSelector: View {
    @Binding var metric: OverviewMetric
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: PadzySpace.l) {
            ForEach(OverviewMetric.allCases) { option in
                let isActive = option == metric
                Button {
                    if reduceMotion { metric = option }
                    else { withAnimation(PadzyMotion.toggle) { metric = option } }
                } label: {
                    VStack(spacing: 5) {
                        Text(option.title)
                            .font(.sans(size: 12.5, weight: .medium))
                            .foregroundColor(isActive ? PadzyTheme.ink : PadzyTheme.ink5)
                        Rectangle()
                            .fill(isActive ? PadzyTheme.accent : Color.clear)
                            .frame(width: 18, height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A dotted 1px underline sized to its container's width — the mockup's SUBTLE
/// confidence tell under an estimated number (paired with a `.help` tooltip on the
/// number). Never a chip; status is disclosed, not shouted.
struct DottedUnderline: View {
    var color: Color = PadzyTheme.ink5

    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [1.5, 2.5]))
        }
        .frame(height: 1)
        .accessibilityHidden(true)
    }
}

/// Per-provider quota presentation state for the Quota lens. A provider the user
/// enabled live quota for must never silently vanish because its live fetch is down (the
/// 2026-07-21 re-QA bug), and must never sit on a "FETCHING…" that outlives the sync
/// (2026-10-28): it shows a live gauge or a `QuotaGap` that says why there is none.
enum ProviderQuotaState: Equatable {
    case live(Utilization)
    case gap(QuotaGap)

    var isLive: Bool { if case .live = self { return true }; return false }
}

/// One provider's row in the Quota-lens view, carrying its resolved state.
struct AgentQuotaRow: Identifiable {
    let id: ProviderID
    let name: String
    let state: ProviderQuotaState
    /// Pace of the live window; `nil` for non-live rows or when the window has no honest pace.
    var pace: QuotaPace?

    /// Reset of the live window, for the forecast's lead time; `nil` for non-live rows.
    var resetAt: Date? {
        if case .live(let util) = state { return util.resetAt }
        return nil
    }

    /// The tightest window's used%, or 0 for non-live states (used only to sort).
    var usedPercent: Double {
        if case .live(let util) = state { return util.usedPercent }
        return 0
    }

    /// Live rows first (highest pressure on top), then rows still being checked, then
    /// rows with no reading, then rows whose live quota is off.
    var sortRank: Int {
        switch state {
        case .live: return 0
        case .gap(.checking): return 1
        case .gap(.noReading): return 2
        case .gap(.networkOff): return 3
        case .gap(.noSource): return 4
        }
    }
}

/// Per-agent quota rows (the Quota-lens replacement for the trend line). A live window is
/// a gauge with its percentage, elapsed tick, pace and forecast; a provider without one is
/// a single line saying why, with no empty bar. Fills animate 0→value on appear
/// (reduce-motion safe).
struct AgentQuotaBars: View {
    let rows: [AgentQuotaRow]
    /// Opens a provider's drill-in (a row's name, and "No reading" rows' detail).
    var onSelect: (ProviderID) -> Void = { _ in }
    /// Opens Settings, where each provider's live quota is switched on.
    var onOpenSettings: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = false

    var body: some View {
        VStack(spacing: PadzySpace.m) {
            ForEach(rows) { row in
                switch row.state {
                case .live(let util): liveRow(row, util: util)
                case .gap(let gap): gapRow(row, gap: gap)
                }
            }
        }
        .onAppear {
            if reduceMotion { filled = true } else { withAnimation(PadzyMotion.numberRoll) { filled = true } }
        }
    }

    private func nameLabel(_ row: AgentQuotaRow) -> some View {
        HStack(spacing: PadzySpace.s) {
            ProviderBrandMark.tinted(row.id, size: 16)
            Text(row.name)
                .font(.sans(size: 12, weight: .medium))
                .foregroundColor(PadzyTheme.ink2)
                .lineLimit(1)
        }
    }

    private func liveRow(_ row: AgentQuotaRow, util: Utilization) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: PadzySpace.s) {
                nameLabel(row)
                Spacer(minLength: 8)
                Text("\(Int(round(util.usedPercent)))%")
                    .font(.mono(size: 13.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(PadzyTheme.ink)
                    .rollingNumber(util.usedPercent, reduceMotion: reduceMotion)
            }
            track(util, pace: row.pace)
            if let pace = row.pace {
                PaceLine(pace: pace, resetAt: row.resetAt)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect(row.id) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(row, util: util))
        .accessibilityAddTraits(.isButton)
    }

    /// No gauge to draw: the provider's name, what is going on in words, and the one action
    /// that changes it.
    private func gapRow(_ row: AgentQuotaRow, gap: QuotaGap) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PadzySpace.s) {
            nameLabel(row)
            Text(Self.words(for: gap))
                .font(.sans(size: 15))
                .foregroundColor(PadzyTheme.ink3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            switch gap {
            case .networkOff:
                actionButton("Turn on in Settings", help: "Open Settings › Live quota") { onOpenSettings() }
            case .noReading:
                actionButton("Details", help: "Open \(row.name)") { onSelect(row.id) }
            case .checking, .noSource:
                EmptyView()
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    static func words(for gap: QuotaGap) -> String {
        switch gap {
        case .networkOff: return "Live quota is off"
        case .checking: return "Checking…"
        case .noReading(let reason): return reason.map { "No reading: \($0)" } ?? "No reading from the last sync"
        case .noSource: return "No live quota source"
        }
    }

    private func actionButton(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold))
            }
            .font(.sans(size: 13, weight: .medium))
            .foregroundColor(PadzyTheme.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// The 6pt track with its threshold fill (animated 0→value) and, when the window has a
    /// pace, the elapsed tick standing proud of it.
    private func track(_ util: Utilization, pace: QuotaPace?) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(PadzyTheme.hairline)
                    .frame(height: 6)
                let clamped = max(0, min(100, util.usedPercent))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(PadzyTheme.quotaColor(util.usedPercent))
                    .frame(width: geo.size.width * CGFloat(clamped / 100) * (filled ? 1 : 0), height: 6)
                    .animation(LiveNumberMotion.animation(reduceMotion: reduceMotion), value: clamped)
                if let pace {
                    ElapsedTick(elapsedPercent: pace.elapsedPercent, width: geo.size.width)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: pace == nil ? 6 : 12)
    }

    private func accessibilityLabel(_ row: AgentQuotaRow, util: Utilization) -> String {
        let base = "\(row.name), \(Int(round(util.usedPercent))) percent of quota used"
        guard let pace = row.pace else { return base }
        let forecast = PaceCopy.forecast(pace, resetAt: row.resetAt, now: Date())
        return "\(base). \(PaceCopy.accessibility(pace, forecast: forecast))"
    }
}

/// Measures a view's width so the agent grid can pick a column count from real
/// available space (reflow) rather than a hard-coded breakpoint.
struct OverviewWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

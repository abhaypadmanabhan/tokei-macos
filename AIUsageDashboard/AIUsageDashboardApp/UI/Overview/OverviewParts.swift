import SwiftUI
import AIUsageDashboardCore

/// Which lens the Overview hero + main chart present. `usage` = tokens over time;
/// `quota` = how close each plan is to its ceiling. Local pane state — never Core.
enum OverviewMetric: String, CaseIterable, Identifiable {
    case usage
    case quota

    var id: String { rawValue }
    var title: String {
        switch self {
        case .usage: return "Usage"
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

/// Average tokens per weekday (Mon→Sun). The busiest bar takes the single accent;
/// the rest are dim `ink5`. Bars grow in from the baseline on appear — a static
/// full-height render under Reduce Motion.
struct WeekdayBars: View {
    /// Seven entries, Monday first. `value` is the average tokens for that weekday.
    let bars: [(label: String, value: Int)]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    private let maxHeight: CGFloat = 92
    private var peak: Int { max(bars.map(\.value).max() ?? 0, 1) }
    private var busiestValue: Int { bars.map(\.value).max() ?? 0 }

    var body: some View {
        HStack(alignment: .bottom, spacing: PadzySpace.s) {
            ForEach(bars.indices, id: \.self) { index in
                let bar = bars[index]
                let isBusiest = bar.value == busiestValue && bar.value > 0
                let target = CGFloat(bar.value) / CGFloat(peak) * maxHeight
                let shown = (reduceMotion || grown) ? max(target, bar.value > 0 ? 3 : 0) : 0

                VStack(spacing: 6) {
                    ZStack(alignment: .bottom) {
                        Color.clear.frame(height: maxHeight)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(isBusiest ? PadzyTheme.accent : PadzyTheme.ink5.opacity(0.55))
                            .frame(height: shown)
                    }
                    .frame(maxWidth: .infinity)
                    Text(bar.label)
                        .font(.mono(size: 9))
                        .foregroundColor(isBusiest ? PadzyTheme.ink3 : PadzyTheme.ink5)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(bar.label), \(TokenFormatter.format(bar.value)) average tokens")
            }
        }
        .onAppear {
            guard !reduceMotion else { grown = true; return }
            withAnimation(PadzyMotion.settle) { grown = true }
        }
    }
}

/// Per-provider quota presentation state for the Quota lens. A provider the user
/// enabled live quota for must NEVER silently vanish just because its live fetch is
/// transiently down (cooldown / 429 / auth / empty) — the 2026-07-21 re-QA "Claude &
/// Antigravity missing from Quota" bug. We surface an honest state instead of omitting.
enum ProviderQuotaState {
    case live(Utilization)   // a real live window with a usable percentage
    case fetching            // connectable + live-enabled, but no window right now
    case connect             // connectable, live quota not enabled yet
    case localOnly           // no online connector (codex / cline) and no local quota

    var isLive: Bool { if case .live = self { return true }; return false }
}

/// One provider's row in the Quota-lens bar view, carrying its resolved state.
struct AgentQuotaRow: Identifiable {
    let id: ProviderID
    let name: String
    let state: ProviderQuotaState

    /// The tightest window's used%, or 0 for non-live states (used only to sort).
    var usedPercent: Double {
        if case .live(let util) = state { return util.usedPercent }
        return 0
    }

    /// Live rows first (highest pressure on top), then enabled-but-fetching, then
    /// connect prompts, then local-only — so an enabled provider never sinks below
    /// a disconnected one, and nothing the user enabled is dropped.
    var sortRank: Int {
        switch state {
        case .live: return 0
        case .fetching: return 1
        case .connect: return 2
        case .localOnly: return 3
        }
    }
}

/// Per-agent quota bars (the Quota-metric replacement for the trend line): every
/// visible provider gets a row — a live window shows a threshold-coloured fill + %,
/// while a provider with no live window shows its honest state (fetching / enable /
/// local-only) rather than disappearing. Fills animate 0→value on appear
/// (reduce-motion safe).
struct AgentQuotaBars: View {
    let rows: [AgentQuotaRow]
    /// Tapping an "ENABLE →" row opens that provider's detail (where live quota is
    /// turned on).
    var onConnect: (ProviderID) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = false

    var body: some View {
        if rows.isEmpty {
            emptyState
        } else {
            VStack(spacing: PadzySpace.m) {
                ForEach(rows) { row in
                    quotaRow(row)
                }
            }
            .onAppear {
                if reduceMotion { filled = true }
                else { withAnimation(PadzyMotion.settle) { filled = true } }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NO LIVE QUOTA CONNECTED")
                .font(.mono(size: 11))
                .tracking(11 * 0.08)
                .foregroundColor(PadzyTheme.ink3)
            Text("Connect a plan's live quota to see how close each agent is to its ceiling.")
                .font(.sans(size: 12))
                .foregroundColor(PadzyTheme.ink4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func quotaRow(_ row: AgentQuotaRow) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: PadzySpace.s) {
                ProviderBrandMark.tinted(row.id, size: 16)
                Text(row.name)
                    .font(.sans(size: 12, weight: .medium))
                    .foregroundColor(PadzyTheme.ink2)
                    .lineLimit(1)
                Spacer(minLength: 8)
                trailing(row.state)
            }
            track(row.state)
        }
        .contentShape(Rectangle())
        .onTapGesture { if case .connect = row.state { onConnect(row.id) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(row))
    }

    /// The trailing figure/label: `%` for a live window (threshold-coloured), else a
    /// muted status word (or an accent ENABLE → action).
    @ViewBuilder
    private func trailing(_ state: ProviderQuotaState) -> some View {
        switch state {
        case .live(let util):
            Text("\(Int(round(util.usedPercent)))%")
                .font(.mono(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.quotaColor(util.usedPercent))
        case .fetching:
            Text("FETCHING…").font(.mono(size: 10)).foregroundColor(PadzyTheme.ink5)
        case .connect:
            Text("ENABLE →").font(.mono(size: 10)).foregroundColor(PadzyTheme.accent)
        case .localOnly:
            Text("LOCAL LOGS").font(.mono(size: 10)).foregroundColor(PadzyTheme.ink5)
        }
    }

    /// The 6pt track: a threshold fill for live rows (animated 0→value), a faint
    /// hairline track alone for the non-live states.
    @ViewBuilder
    private func track(_ state: ProviderQuotaState) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(PadzyTheme.hairline)
                if case .live(let util) = state {
                    let clamped = max(0, min(100, util.usedPercent))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(PadzyTheme.quotaColor(util.usedPercent))
                        .frame(width: geo.size.width * CGFloat(clamped / 100) * (filled ? 1 : 0))
                }
            }
        }
        .frame(height: 6)
    }

    private func accessibilityLabel(_ row: AgentQuotaRow) -> String {
        switch row.state {
        case .live(let util):
            return "\(row.name), \(Int(round(util.usedPercent))) percent of quota used"
        case .fetching:
            return "\(row.name), live quota enabled, fetching"
        case .connect:
            return "\(row.name), live quota not connected. Opens \(row.name) detail to enable."
        case .localOnly:
            return "\(row.name), local logs only, no live quota"
        }
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

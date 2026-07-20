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

/// Per-agent quota bars (the Quota-metric replacement for the trend line): agent
/// mark + name, a track with a `quotaColor` fill, and the percentage. Sorted
/// desc by the caller. Honest empty state when nothing reports live quota.
struct AgentQuotaBars: View {
    let bars: [(id: ProviderID, name: String, pct: Double)]

    var body: some View {
        if bars.isEmpty {
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
        } else {
            VStack(spacing: PadzySpace.m) {
                ForEach(bars, id: \.id) { bar in
                    let clamped = max(0, min(100, bar.pct))
                    VStack(spacing: 6) {
                        HStack(spacing: PadzySpace.s) {
                            ProviderBrandMark.tinted(bar.id, size: 16)
                            Text(bar.name)
                                .font(.sans(size: 12, weight: .medium))
                                .foregroundColor(PadzyTheme.ink2)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(Int(round(bar.pct)))%")
                                .font(.mono(size: 12, weight: .semibold))
                                .monospacedDigit()
                                .foregroundColor(PadzyTheme.quotaColor(bar.pct))
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(PadzyTheme.hairline)
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(PadzyTheme.quotaColor(bar.pct))
                                    .frame(width: geo.size.width * CGFloat(clamped / 100))
                            }
                        }
                        .frame(height: 6)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(bar.name), \(Int(round(bar.pct))) percent of quota used")
                }
            }
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

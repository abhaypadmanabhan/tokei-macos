import SwiftUI

/// Rounded surface card shell for the redesigned dashboard (design spec §3):
/// caps-mono kicker title, optional trailing control, content on a
/// `PadzyRadius.card` surface panel with a 1px hairline stroke. No shadows,
/// no materials — the lift comes from surface-over-ground plus the hairline.
struct SectionCard<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    init(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Text(title.uppercased())
                    .font(.mono(size: 11))
                    .tracking(11 * 0.08)
                    .foregroundColor(PadzyTheme.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                trailing
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PadzyRadius.card, style: .continuous)
                .fill(PadzyTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PadzyRadius.card, style: .continuous)
                .stroke(PadzyTheme.muted.opacity(0.22), lineWidth: 1)
        )
    }
}

/// KPI tile: caps-mono kicker, large mono value, optional signed delta and
/// optional per-metric sparkline. Sits inside or alongside `SectionCard`s;
/// `boxed: false` renders bare for use inside an existing card.
struct StatCard: View {
    let kicker: String
    let value: String
    var delta: Double? = nil
    var deltaCaption: String? = nil
    var sparklineValues: [Int]? = nil
    var sparklineTint: Color = PadzyTheme.ink.opacity(0.55)
    var boxed: Bool = true

    var body: some View {
        let stack = VStack(alignment: .leading, spacing: 6) {
            Text(kicker.uppercased())
                .font(.mono(size: 10))
                .tracking(10 * 0.08)
                .foregroundColor(PadzyTheme.muted)
                .lineLimit(1)

            Text(value)
                .font(.mono(size: 24))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let delta {
                DeltaLabel(delta: delta, caption: deltaCaption)
            }

            if let sparklineValues {
                MetricSparkline(values: sparklineValues, tint: sparklineTint)
                    .frame(height: 22)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if boxed {
            stack
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                        .fill(PadzyTheme.ground.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                        .stroke(PadzyTheme.muted.opacity(0.18), lineWidth: 1)
                )
        } else {
            stack
        }
    }
}

/// Signed percent delta ("▲ +18.2% vs yesterday"). Direction carried by BOTH
/// the glyph/sign and the hue (never color alone). One of the few sanctioned
/// homes for `PadzyChartPalette` outside a chart body.
struct DeltaLabel: View {
    let delta: Double
    var caption: String? = nil

    private var glyph: String { delta >= 0 ? "▲" : "▼" }
    private var tint: Color { delta >= 0 ? PadzyChartPalette.deltaUp : PadzyChartPalette.deltaDown }
    private var formatted: String {
        // True minus sign for negatives (dataviz number-formatting rule).
        let sign = delta >= 0 ? "+" : "−"
        return "\(sign)\(String(format: "%.1f", abs(delta)))%"
    }

    var body: some View {
        HStack(spacing: 5) {
            Text("\(glyph) \(formatted)")
                .font(.mono(size: 11))
                .monospacedDigit()
                .foregroundColor(tint)
            if let caption {
                Text(caption.uppercased())
                    .font(.mono(size: 10))
                    .foregroundColor(PadzyTheme.muted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(delta >= 0 ? "up" : "down") \(String(format: "%.1f", abs(delta))) percent\(caption.map { " \($0)" } ?? "")")
    }
}

// MARK: - Previews

#Preview("SectionCard + StatCards") {
    VStack(spacing: 16) {
        SectionCard("Today", trailing: {
            Text("LIVE")
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.muted)
        }) {
            HStack(spacing: 10) {
                StatCard(kicker: "Input", value: "12.4M", delta: 18.2, deltaCaption: "vs yesterday",
                         sparklineValues: [3, 5, 4, 8, 6, 9, 12], sparklineTint: PadzyChartPalette.input)
                StatCard(kicker: "Output", value: "1.9M", delta: -6.4,
                         sparklineValues: [9, 7, 8, 5, 6, 4, 3], sparklineTint: PadzyChartPalette.output)
                StatCard(kicker: "Cache read", value: "48.1M",
                         sparklineValues: [2, 6, 5, 9, 7, 11, 10], sparklineTint: PadzyChartPalette.cacheRead)
            }
        }

        SectionCard("Bare tiles") {
            HStack(spacing: 24) {
                StatCard(kicker: "Streak", value: "14 DAYS", boxed: false)
                StatCard(kicker: "Daily avg", value: "9.1M", boxed: false)
            }
        }
    }
    .padding(24)
    .frame(width: 640)
    .background(PadzyTheme.ground)
}

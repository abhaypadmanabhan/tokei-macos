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

#Preview("SectionCard") {
    SectionCard("Today") {
        Text("Local usage")
            .font(.sans(size: 15))
            .foregroundColor(PadzyTheme.ink)
    }
    .padding(24)
    .frame(width: 640)
    .background(PadzyTheme.ground)
}

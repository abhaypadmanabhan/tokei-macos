import SwiftUI

/// Sparkline for a short numeric series (daily token totals, per-metric trends).
/// Relocated from `TokeiMark.swift` and given a `tint` so hero tiles can carry
/// their per-metric `PadzyChartPalette` hue (design spec §3). Defaults to the
/// original ink treatment. Flat hairline when fewer than 2 points — an honest
/// "not enough history" rendering, never a fake flat-zero line.
struct MetricSparkline: View {
    let values: [Int]
    var tint: Color = PadzyTheme.ink.opacity(0.55)

    var body: some View {
        GeometryReader { geo in
            if values.count >= 2, let maxValue = values.max(), maxValue > 0 {
                Path { path in
                    let stepX = geo.size.width / CGFloat(values.count - 1)
                    for (i, v) in values.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = geo.size.height * (1 - CGFloat(v) / CGFloat(maxValue) * 0.9)
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            } else {
                Rectangle()
                    .fill(PadzyTheme.muted.opacity(0.4))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

#Preview("Sparkline states") {
    VStack(alignment: .leading, spacing: 20) {
        MetricSparkline(values: [3, 6, 4, 9, 7, 12, 10]).frame(height: 32)
        MetricSparkline(values: [3, 6, 4, 9, 7, 12, 10], tint: PadzyChartPalette.input).frame(height: 32)
        MetricSparkline(values: [3, 6, 4, 9, 7, 12, 10], tint: PadzyChartPalette.output).frame(height: 32)
        MetricSparkline(values: [5]).frame(height: 32)   // not enough history → hairline
        MetricSparkline(values: []).frame(height: 32)    // empty → hairline
    }
    .padding(24)
    .frame(width: 320)
    .background(PadzyTheme.ground)
}

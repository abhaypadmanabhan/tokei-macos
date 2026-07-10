import SwiftUI

/// Compact sparkline-scale area fill (design spec §3) — the mini trend inside
/// rolling cards and the menu-bar popover hero. No axes, no labels: an accent
/// line over the sanctioned pink→transparent gradient. Index-based x, so it
/// takes a bare value series. Hairline when history < 2 points (matches
/// `MetricSparkline`'s honest empty rendering).
struct AreaTrendChart: View {
    let values: [Int]
    var tint: Color = PadzyTheme.accent

    var body: some View {
        GeometryReader { geo in
            if values.count >= 2, let maxValue = values.max(), maxValue > 0 {
                let line = linePath(in: geo.size)
                ZStack {
                    areaPath(in: geo.size)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.28), tint.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    line.stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            } else {
                Rectangle()
                    .fill(PadzyTheme.muted.opacity(0.4))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private func point(_ i: Int, in size: CGSize) -> CGPoint {
        let maxValue = CGFloat(values.max() ?? 1)
        let stepX = size.width / CGFloat(values.count - 1)
        let y = size.height * (1 - CGFloat(values[i]) / maxValue * 0.9)
        return CGPoint(x: CGFloat(i) * stepX, y: y)
    }

    private func linePath(in size: CGSize) -> Path {
        Path { path in
            for i in values.indices {
                let p = point(i, in: size)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        }
    }

    private func areaPath(in size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: size.height))
            for i in values.indices {
                path.addLine(to: point(i, in: size))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
        }
    }
}

#Preview("Area trend states") {
    VStack(alignment: .leading, spacing: 20) {
        AreaTrendChart(values: [3, 6, 4, 9, 7, 12, 10]).frame(height: 40)
        AreaTrendChart(values: [12, 8, 10, 6, 7, 4, 5], tint: PadzyChartPalette.output).frame(height: 40)
        AreaTrendChart(values: [5]).frame(height: 40)   // not enough history → hairline
        AreaTrendChart(values: []).frame(height: 40)
    }
    .padding(24)
    .frame(width: 320)
    .background(PadzyTheme.ground)
}

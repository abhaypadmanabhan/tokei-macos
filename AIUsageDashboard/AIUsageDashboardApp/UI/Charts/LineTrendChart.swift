import SwiftUI
import Charts

/// Token-usage-over-time line (WP-5 mockup). A neutral `ink2` line over the one
/// sanctioned neutral area gradient, a faint dashed cap line near the top, an
/// accent end dot + value label on the most recent point, muted mono axes with
/// relative day labels. Plain value inputs — no view-model coupling. Honest empty
/// state when history < 2 points.
struct LineTrendChart: View {
    let points: [(date: Date, tokens: Int)]

    private struct Point: Identifiable {
        let id: Int
        let date: Date
        let tokens: Int
    }

    private var series: [Point] {
        points.enumerated().map { Point(id: $0.offset, date: $0.element.date, tokens: $0.element.tokens) }
    }

    var body: some View {
        if series.count >= 2 {
            chart
        } else {
            emptyState
        }
    }

    private var chart: some View {
        let last = series.last
        // Faint dashed ceiling near the top — a visual cap the line reaches toward.
        let cap = series.map(\.tokens).max()
        return Chart {
            ForEach(series) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Tokens", point.tokens)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(PadzyChartPalette.areaGradient)

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Tokens", point.tokens)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(PadzyTheme.ink2)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))

                if let last, point.id == last.id {
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Tokens", point.tokens)
                    )
                    .symbolSize(46)
                    .foregroundStyle(PadzyTheme.accent)
                    .annotation(position: .topTrailing, spacing: 4) {
                        Text(TokenFormatter.format(point.tokens))
                            .font(.mono(size: 10))
                            .monospacedDigit()
                            .foregroundColor(PadzyTheme.ink)
                    }
                }
            }

            if let cap {
                RuleMark(y: .value("Peak", cap))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(PadzyTheme.hairline)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Self.relativeLabel(date))
                            .font(.mono(size: 10))
                            .foregroundStyle(PadzyTheme.ink5)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(PadzyTheme.hairline.opacity(0.8))
                AxisValueLabel {
                    if let tokens = value.as(Int.self) {
                        Text(TokenFormatter.format(tokens))
                            .font(.mono(size: 10))
                            .foregroundStyle(PadzyTheme.ink5)
                    }
                }
            }
        }
        .chartLegend(.hidden)
    }

    /// Relative day label for the x-axis: `TODAY` for the current day, else the
    /// whole-day distance back (`7D`). Mono ink5, matching the mockup's minimal
    /// axis — dates read as "how long ago", not a calendar.
    private static func relativeLabel(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        return days <= 0 ? "TODAY" : "\(days)D"
    }

    /// Chart-state contract (dataviz): the frame stays, a caps micro label names
    /// the absence. No shimmer, no fake series.
    private var emptyState: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                .fill(PadzyTheme.ground.opacity(0.4))
            Text(points.isEmpty ? "NO USAGE RECORDED" : "NOT ENOUGH HISTORY YET")
                .font(.mono(size: 11))
                .tracking(11 * 0.08)
                .foregroundColor(PadzyTheme.muted)
        }
    }
}

// MARK: - Previews

private func samplePoints(_ days: Int) -> [(date: Date, tokens: Int)] {
    let base = Date(timeIntervalSince1970: 1_767_000_000)
    let values = [4_200_000, 9_800_000, 7_400_000, 15_200_000, 11_100_000,
                  18_600_000, 9_300_000, 21_400_000, 16_800_000, 12_500_000,
                  24_100_000, 19_700_000, 14_300_000, 20_900_000]
    return (0..<days).map { i in
        (date: base.addingTimeInterval(Double(i) * 86_400), tokens: values[i % values.count])
    }
}

#Preview("14 days") {
    LineTrendChart(points: samplePoints(14))
        .frame(width: 560, height: 220)
        .padding(24)
        .background(PadzyTheme.ground)
}

#Preview("7 days") {
    LineTrendChart(points: samplePoints(7))
        .frame(width: 560, height: 220)
        .padding(24)
        .background(PadzyTheme.ground)
}

#Preview("Empty + single point") {
    VStack(spacing: 16) {
        LineTrendChart(points: []).frame(height: 140)
        LineTrendChart(points: samplePoints(1)).frame(height: 140)
    }
    .frame(width: 560)
    .padding(24)
    .background(PadzyTheme.ground)
}

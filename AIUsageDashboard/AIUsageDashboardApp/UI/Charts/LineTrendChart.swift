import SwiftUI
import Charts

/// Token-usage-over-time line (WP-5 mockup). A neutral `ink2` line over the one
/// sanctioned neutral area gradient, a faint dashed cap line near the top, an
/// accent end dot + value label on the most recent point, muted mono axes with
/// relative day labels. Plain value inputs — no view-model coupling. Honest empty
/// state when history < 2 points.
/// Per-day hover detail for the trend callout: the agent that led that day and its
/// identity tint. Both optional — a call site with no per-agent split still gets a
/// date + total callout.
struct TrendPointDetail: Equatable {
    var topAgent: String?
    var tint: Color?
}

struct LineTrendChart: View {
    let points: [(date: Date, tokens: Int)]
    /// Per-agent identity tint (WP-5 daily history). `nil` keeps the neutral
    /// `ink2` line + sanctioned neutral area gradient — every existing call site
    /// is pixel-identical. When set, the line + area take the agent's DATA colour.
    var tint: Color?
    /// Hover detail keyed by the point's start-of-day date. Empty → the hover callout
    /// shows date + total only (no top-agent line).
    var pointDetails: [Date: TrendPointDetail] = [:]
    /// How a value reads on the axis, the last point and the hover callout. Tokens by
    /// default; Overview › Cost passes whole cents with a dollar format.
    var format: (Int) -> String = { TokenFormatter.format($0) }
    /// Days with no value (Overview › Cost: tokens without a per-model breakdown, or after the
    /// data ends). The line breaks there and a dashed rule says why; it never bridges them.
    var breaks: [Date] = []
    /// What the empty frame says when there are fewer than two points.
    var emptyText: String?

    /// The series index under the pointer (nil when not hovering).
    @State private var hoveredID: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Line stroke: the agent tint when tinted, else the neutral `ink2` default.
    private var lineStyle: Color { tint ?? PadzyTheme.ink2 }

    /// Area fill: a matching low-opacity tint gradient when tinted, else the one
    /// sanctioned neutral area gradient.
    private var areaStyle: AnyShapeStyle {
        if let tint {
            return AnyShapeStyle(LinearGradient(
                colors: [tint.opacity(0.14), tint.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
        return AnyShapeStyle(PadzyChartPalette.areaGradient)
    }

    private struct Point: Identifiable {
        let id: Int
        let date: Date
        let tokens: Int
        /// Points between two breaks share a segment; a line is drawn within a segment only.
        let segment: Int
    }

    private var series: [Point] {
        points.enumerated().map { index, point in
            Point(id: index, date: point.date, tokens: point.tokens,
                  segment: breaks.filter { $0 < point.date }.count)
        }
    }

    /// The first day of each run of consecutive breaks, where the "no price data" label goes.
    private var breakLabels: [Date] {
        let sorted = breaks.sorted()
        return sorted.enumerated().compactMap { index, day in
            guard index > 0, let previous = Calendar.current.date(byAdding: .day, value: 1, to: sorted[index - 1]),
                  Calendar.current.isDate(previous, inSameDayAs: day) else { return day }
            return nil
        }
    }

    /// The point currently under the pointer.
    private var hoveredPoint: Point? {
        guard let hoveredID else { return nil }
        return series.first { $0.id == hoveredID }
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
                    y: .value("Tokens", point.tokens),
                    series: .value("Segment", point.segment)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(areaStyle)

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Tokens", point.tokens),
                    series: .value("Segment", point.segment)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(lineStyle)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))

                // A day standing alone between breaks has no line: give it a dot.
                if !breaks.isEmpty, series.filter({ $0.segment == point.segment }).count == 1 {
                    PointMark(x: .value("Date", point.date), y: .value("Tokens", point.tokens))
                        .symbolSize(24)
                        .foregroundStyle(lineStyle)
                }

                if let last, point.id == last.id {
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Tokens", point.tokens)
                    )
                    .symbolSize(46)
                    .foregroundStyle(PadzyTheme.accent)
                    .annotation(position: .topTrailing, spacing: 4) {
                        Text(format(point.tokens))
                            .font(.mono(size: 13.5))
                            .monospacedDigit()
                            .foregroundColor(PadzyTheme.ink)
                            .rollingNumber(Double(point.tokens), reduceMotion: reduceMotion)
                    }
                }
            }

            ForEach(breaks, id: \.self) { day in
                RuleMark(x: .value("Date", day))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .foregroundStyle(PadzyTheme.hairline)
                    .annotation(
                        position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        if breakLabels.contains(day) {
                            Text("no price data")
                                .font(.sans(size: 11))
                                .foregroundColor(PadzyTheme.ink5)
                        }
                    }
            }

            if let cap {
                RuleMark(y: .value("Peak", cap))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(PadzyTheme.hairline)
            }

            if let hoveredPoint {
                RuleMark(x: .value("Date", hoveredPoint.date))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(PadzyTheme.ink5.opacity(0.7))
                    .annotation(
                        position: .top,
                        spacing: 6,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        hoverCallout(for: hoveredPoint)
                    }

                PointMark(
                    x: .value("Date", hoveredPoint.date),
                    y: .value("Tokens", hoveredPoint.tokens)
                )
                .symbolSize(60)
                .foregroundStyle(lineStyle)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(ChartDayLabel.relative(date))
                            .font(.mono(size: 11))
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
                        Text(format(tokens))
                            .font(.mono(size: 13.5))
                            .foregroundStyle(PadzyTheme.ink5)
                            .rollingNumber(Double(tokens), reduceMotion: reduceMotion)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            // `plotAreaFrame` is a non-optional anchor (works on the
                            // macOS 14 deployment target); the optional `plotFrame`
                            // resolves to nil here and would suppress every hover.
                            let origin = geo[proxy.plotAreaFrame].origin
                            let relativeX = location.x - origin.x
                            guard let date: Date = proxy.value(atX: relativeX) else {
                                hoveredID = nil
                                return
                            }
                            hoveredID = nearestPoint(to: date)?.id
                        case .ended:
                            hoveredID = nil
                        }
                    }
            }
        }
    }

    /// The series point whose date is closest to a hovered x-position.
    private func nearestPoint(to date: Date) -> Point? {
        series.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    /// Padzy hairline callout: that day's date, its total tokens, and (when the
    /// per-agent split is supplied) the agent that led the day with its identity dot.
    private func hoverCallout(for point: Point) -> some View {
        let detail = pointDetails[Calendar.current.startOfDay(for: point.date)]
        return VStack(alignment: .leading, spacing: 3) {
            Text(ChartDayLabel.callout(point.date))
                .font(.mono(size: 11))
                .foregroundColor(PadzyTheme.ink4)
            Text(format(point.tokens))
                .font(.mono(size: 13.5, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink)
                .rollingNumber(Double(point.tokens), reduceMotion: reduceMotion)
            if let agent = detail?.topAgent {
                HStack(spacing: 5) {
                    Circle()
                        .fill(detail?.tint ?? PadzyTheme.ink4)
                        .frame(width: 6, height: 6)
                    Text(agent)
                        .font(.sans(size: 10))
                        .foregroundColor(PadzyTheme.ink3)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                .fill(PadzyTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                .stroke(PadzyTheme.border2, lineWidth: 1)
        )
        .fixedSize()
    }

    /// Chart-state contract (dataviz): the frame stays, a short sentence names the absence.
    /// No shimmer, no fake series.
    private var emptyState: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                .fill(PadzyTheme.ground.opacity(0.4))
            Text(emptyText ?? (points.isEmpty ? "No usage recorded" : "Not enough history yet"))
                .font(.sans(size: 13))
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
    return (0..<days).map { offset in
        (date: base.addingTimeInterval(Double(offset) * 86_400),
         tokens: values[offset % values.count])
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

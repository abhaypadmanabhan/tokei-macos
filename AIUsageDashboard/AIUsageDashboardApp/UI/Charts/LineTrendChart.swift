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
    var tint: Color? = nil
    /// Hover detail keyed by the point's start-of-day date. Empty → the hover callout
    /// shows date + total only (no top-agent line).
    var pointDetails: [Date: TrendPointDetail] = [:]

    /// The series index under the pointer (nil when not hovering).
    @State private var hoveredID: Int?

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
    }

    private var series: [Point] {
        points.enumerated().map { Point(id: $0.offset, date: $0.element.date, tokens: $0.element.tokens) }
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
                    y: .value("Tokens", point.tokens)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(areaStyle)

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Tokens", point.tokens)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(lineStyle)
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
            Text(Self.calloutDate(point.date))
                .font(.mono(size: 9))
                .tracking(0.3)
                .foregroundColor(PadzyTheme.ink5)
            Text(TokenFormatter.format(point.tokens))
                .font(.mono(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink)
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

    private static func calloutDate(_ date: Date) -> String {
        Self.calloutFormatter.string(from: date)
    }

    private static let calloutFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d"
        return formatter
    }()

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

import SwiftUI
import Charts

/// Several accounts of ONE provider drawn on ONE pair of axes.
///
/// Deliberately not "two `LineTrendChart`s stacked": each of those scales its own y-axis to
/// its own peak, so an account using a tenth of another's tokens would draw an identical-
/// looking hill. The whole question this answers — *which account is spending more* — is a
/// comparison, and a comparison needs a shared scale.
///
/// Series are distinguished by colour **and** stroke pattern, so the chart survives being
/// read by someone who cannot separate the hues, and the legend rows below it (owned by the
/// call site) can show the same stroke as a swatch.
struct AccountTrendChart: View {
    /// One day of one account. A named type rather than a tuple: `Chart` builders get very
    /// slow to type-check over tuple arrays.
    struct Point: Identifiable {
        let date: Date
        let tokens: Int
        var id: Date { date }

        init(date: Date, tokens: Int) {
            self.date = date
            self.tokens = tokens
        }
    }

    struct Series: Identifiable {
        /// Stable account id — also the Charts series key.
        let id: String
        let label: String
        let color: Color
        let dash: [CGFloat]
        /// Oldest → newest, one entry per day in the window (zero-filled).
        let points: [Point]
    }

    let series: [Series]

    /// The day under the pointer, snapped to a real bucket.
    @State private var hoveredDay: Date?

    /// Every day any account recorded, ascending — the x domain and the hover buckets.
    private var days: [Date] {
        Array(Set(series.flatMap { $0.points.map(\.date) })).sorted()
    }

    private var hasEnoughHistory: Bool { days.count >= 2 }

    var body: some View {
        if hasEnoughHistory {
            chart
        } else {
            emptyState
        }
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            ForEach(series) { line in
                ForEach(line.points) { point in
                    LineMark(
                        x: .value("Day", point.date),
                        y: .value("Tokens", point.tokens),
                        series: .value("Account", line.id)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(line.color)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineJoin: .round, dash: line.dash))
                }
            }

            if let hoveredDay {
                RuleMark(x: .value("Day", hoveredDay))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(PadzyTheme.ink5.opacity(0.7))
                    .annotation(
                        position: .top,
                        spacing: 6,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        callout(for: hoveredDay)
                    }

                ForEach(series) { line in
                    if let point = line.points.first(where: { $0.date == hoveredDay }) {
                        PointMark(
                            x: .value("Day", point.date),
                            y: .value("Tokens", point.tokens)
                        )
                        .symbolSize(52)
                        .foregroundStyle(line.color)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Self.relativeLabel(date))
                            .font(.mono(size: 13.5))
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
                            .font(.mono(size: 13.5))
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
                            // `plotAreaFrame` is the non-optional anchor that works on the
                            // macOS 14 deployment target (see `LineTrendChart`).
                            let origin = geo[proxy.plotAreaFrame].origin
                            guard let date: Date = proxy.value(atX: location.x - origin.x) else {
                                hoveredDay = nil
                                return
                            }
                            hoveredDay = nearestDay(to: date)
                        case .ended:
                            hoveredDay = nil
                        }
                    }
            }
        }
    }

    private func nearestDay(to date: Date) -> Date? {
        days.min { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) }
    }

    /// That day, every account, biggest first — the direct answer to "who spent more on
    /// this day", without asking anyone to eyeball two lines.
    private func callout(for day: Date) -> some View {
        let rows: [CalloutRow] = series
            .compactMap { line in
                guard let point = line.points.first(where: { $0.date == day }) else { return nil }
                return CalloutRow(id: line.id, label: line.label, color: line.color,
                                  dash: line.dash, tokens: point.tokens)
            }
            .sorted { $0.tokens > $1.tokens }

        return VStack(alignment: .leading, spacing: 5) {
            Text(Self.calloutFormatter.string(from: day))
                .font(.mono(size: 13.5))
                .foregroundColor(PadzyTheme.ink5)
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    StrokeSwatch(color: row.color, dash: row.dash)
                    Text(row.label)
                        .font(.sans(size: 15))
                        .foregroundColor(PadzyTheme.ink3)
                        .lineLimit(1)
                    Spacer(minLength: 10)
                    Text(TokenFormatter.format(row.tokens))
                        .font(.mono(size: 13.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(PadzyTheme.ink)
                }
            }
        }
        .padding(.horizontal, PadzySpace.m)
        .padding(.vertical, PadzySpace.s)
        .background(
            RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                .fill(PadzyTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                .stroke(PadzyTheme.border2, lineWidth: 1)
        )
        .frame(minWidth: 180)
        .fixedSize()
    }

    private struct CalloutRow: Identifiable {
        let id: String
        let label: String
        let color: Color
        let dash: [CGFloat]
        let tokens: Int
    }

    /// Same relative-day idiom as the provider history chart: how long ago, not a calendar.
    private static func relativeLabel(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        return days <= 0 ? "TODAY" : "\(days)D"
    }

    private static let calloutFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d"
        return formatter
    }()

    /// Chart-state contract: the frame stays, a label names the absence, no fake series.
    private var emptyState: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                .fill(PadzyTheme.ground.opacity(0.4))
            Text(days.isEmpty ? "NO PER-ACCOUNT HISTORY YET" : "ONLY ONE DAY SO FAR")
                .font(.mono(size: 13.5))
                .tracking(13.5 * 0.08)
                .foregroundColor(PadzyTheme.muted)
        }
    }
}

/// The legend key for one series: a short run of the line itself, dash and all. A line, not
/// a dot — a coloured dot would be reading as status, and this is identity.
struct StrokeSwatch: View {
    let color: Color
    var dash: [CGFloat] = []
    var width: CGFloat = 20

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 1))
            path.addLine(to: CGPoint(x: width, y: 1))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .butt, dash: dash))
        .frame(width: width, height: 2)
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

private func sampleSeries(_ label: String, id: String, index: Int, scale: Double) -> AccountTrendChart.Series {
    let base = Date(timeIntervalSince1970: 1_767_000_000)
    let values = [4_200_000, 9_800_000, 7_400_000, 15_200_000, 11_100_000,
                  18_600_000, 9_300_000, 21_400_000, 16_800_000, 12_500_000]
    return AccountTrendChart.Series(
        id: id,
        label: label,
        color: AccountSeriesStyle.color(index, tint: AgentTint.color(.claudeCode)),
        dash: AccountSeriesStyle.dash(index),
        points: (0..<10).map { i in
            AccountTrendChart.Point(
                date: base.addingTimeInterval(Double(i) * 86_400),
                tokens: Int(Double(values[i]) * scale)
            )
        }
    )
}

#Preview("Two accounts") {
    AccountTrendChart(series: [
        sampleSeries("default", id: "a", index: 0, scale: 1),
        sampleSeries("account-1", id: "b", index: 1, scale: 0.35),
    ])
    .frame(width: 420, height: 180)
    .padding(24)
    .background(PadzyTheme.ground)
}

#Preview("Three accounts") {
    AccountTrendChart(series: [
        sampleSeries("default", id: "a", index: 0, scale: 1),
        sampleSeries("account-1", id: "b", index: 1, scale: 0.35),
        sampleSeries("account-2", id: "c", index: 2, scale: 0.7),
    ])
    .frame(width: 420, height: 180)
    .padding(24)
    .background(PadzyTheme.ground)
}

#Preview("Empty") {
    AccountTrendChart(series: [])
        .frame(width: 420, height: 180)
        .padding(24)
        .background(PadzyTheme.ground)
}

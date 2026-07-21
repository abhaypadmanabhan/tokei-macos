import SwiftUI

/// Weekday × hour activity punch-card: 7 weekday rows × 24 hour columns of
/// **square** cells (the standard GitHub-punchcard shape), so the grid reads as
/// structure you can scan — which days, which hours — instead of a smear.
///
/// WP-5 note: an earlier build filled cells with a *continuous* single-hue
/// opacity in *wide* rectangles, which read as noise. This version fixes both —
/// square cells at a fixed size (left-aligned, never stretched), every cell a
/// visible box (empty = faint grid box), and **4 discrete intensity steps** so a
/// busy hour is a clear block, not a slightly-different gray. Still one neutral
/// hue (activity is DATA, never the accent). Honest empty state until a real
/// hourly source exists.
struct ActivityHeatmap: View {
    /// 7 rows (Mon…Sun) × 24 columns (hour 0…23); `nil` = no data for that cell.
    let matrix: [[Int?]]
    /// Copy under the empty-state headline (names the missing source).
    var emptyHint: String = "Hourly activity appears once local logs are parsed with per-hour timestamps."

    @State private var width: CGFloat = 0

    private static let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private static let hourMarks: [(column: Int, label: String)] = [
        (0, "12a"), (6, "6a"), (12, "12p"), (18, "6p"),
    ]

    // Layout constants. Cells are square and fixed-size (capped) so the grid keeps
    // a legible punch-card scale on both a 640pt and an 1100pt window.
    private static let labelWidth: CGFloat = 28
    private static let labelGap: CGFloat = 8
    private static let gap: CGFloat = 2
    private static let minCell: CGFloat = 9
    private static let maxCell: CGFloat = 18
    private static let columns = 24
    private static let rows = 7

    private var hasData: Bool {
        matrix.contains { row in row.contains { ($0 ?? 0) > 0 } }
    }

    private var maxValue: Int {
        matrix.flatMap { $0 }.compactMap { $0 }.max() ?? 0
    }

    /// Square cell side derived from the available width, clamped so it never
    /// stretches into wide rectangles on a large window nor shrinks illegibly.
    private var cell: CGFloat {
        let gridWidth = width - Self.labelWidth - Self.labelGap
        let raw = (gridWidth - Self.gap * CGFloat(Self.columns - 1)) / CGFloat(Self.columns)
        return min(Self.maxCell, max(Self.minCell, raw))
    }

    private var gridWidth: CGFloat { cell * CGFloat(Self.columns) + Self.gap * CGFloat(Self.columns - 1) }
    private var gridHeight: CGFloat { cell * CGFloat(Self.rows) + Self.gap * CGFloat(Self.rows - 1) }

    var body: some View {
        Group {
            if matrix.count == Self.rows, hasData {
                grid
            } else {
                emptyState
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: HeatmapWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(HeatmapWidthKey.self) { width = $0 }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: Self.labelGap) {
                VStack(spacing: Self.gap) {
                    ForEach(Self.weekdays, id: \.self) { day in
                        Text(day)
                            .font(.mono(size: 9))
                            .foregroundColor(PadzyTheme.ink5)
                            .frame(width: Self.labelWidth, height: cell, alignment: .leading)
                    }
                }

                Canvas { context, _ in
                    let peak = Double(max(maxValue, 1))
                    for row in 0..<Self.rows {
                        for column in 0..<Self.columns {
                            let rect = CGRect(
                                x: CGFloat(column) * (cell + Self.gap),
                                y: CGFloat(row) * (cell + Self.gap),
                                width: cell,
                                height: cell
                            )
                            let value = matrix.indices.contains(row) && matrix[row].indices.contains(column)
                                ? matrix[row][column]
                                : nil
                            context.fill(
                                Path(roundedRect: rect, cornerRadius: 2),
                                with: .color(cellColor(value, peak: peak))
                            )
                        }
                    }
                }
                .frame(width: gridWidth, height: gridHeight)
            }

            hourAxis
            legend
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity heatmap by weekday and hour")
    }

    /// Empty cells are a faint but visible box so the grid itself reads; active
    /// cells step through 4 discrete neutral levels (busy → bright), never a
    /// continuous gradient.
    private func cellColor(_ value: Int?, peak: Double) -> Color {
        guard let value, value > 0 else { return PadzyTheme.hairline }
        let intensity = min(1.0, Double(value) / peak)
        let step = Double(min(4, max(1, Int(ceil(intensity * 4))))) / 4.0
        return PadzyChartPalette.heatCell(step)
    }

    private var hourAxis: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Self.hourMarks, id: \.column) { mark in
                Text(mark.label)
                    .font(.mono(size: 9))
                    .foregroundColor(PadzyTheme.ink5)
                    .offset(x: Self.labelWidth + Self.labelGap + CGFloat(mark.column) * (cell + Self.gap))
            }
        }
        .frame(height: 12, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Discrete swatch legend, matching the 4-step cell fills.
    private var legend: some View {
        HStack(spacing: 5) {
            Text("less")
                .font(.mono(size: 9))
                .foregroundColor(PadzyTheme.ink5)
            ForEach(Array(legendSwatches.enumerated()), id: \.offset) { _, color in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 11, height: 11)
            }
            Text("more")
                .font(.mono(size: 9))
                .foregroundColor(PadzyTheme.ink5)
        }
        .padding(.top, 2)
    }

    private var legendSwatches: [Color] {
        [PadzyTheme.hairline,
         PadzyChartPalette.heatCell(0.25),
         PadzyChartPalette.heatCell(0.5),
         PadzyChartPalette.heatCell(0.75),
         PadzyChartPalette.heatCell(1.0)]
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NO HOURLY DATA YET")
                .font(.mono(size: 11))
                .tracking(11 * 0.08)
                .foregroundColor(PadzyTheme.ink)
            Text(emptyHint)
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                .fill(PadzyTheme.ground.opacity(0.4))
        )
    }
}

private struct HeatmapWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Previews

private func sampleMatrix() -> [[Int?]] {
    (0..<7).map { row in
        (0..<24).map { hour -> Int? in
            // Workday shape: quiet nights, dense 9–18, lighter weekends.
            guard hour >= 7, hour <= 23 else { return 0 }
            let weekend = row >= 5
            let midday = hour >= 9 && hour <= 18 ? 8 : 2
            return (weekend ? 1 : midday) * ((row + hour) % 4 + 1)
        }
    }
}

#Preview("Full week") {
    ActivityHeatmap(matrix: sampleMatrix())
        .frame(width: 560)
        .padding(24)
        .background(PadzyTheme.ground)
}

#Preview("Narrow 640") {
    ActivityHeatmap(matrix: sampleMatrix())
        .frame(width: 420)
        .padding(24)
        .background(PadzyTheme.ground)
}

#Preview("Empty (Phase 1b gate)") {
    ActivityHeatmap(matrix: [])
        .frame(width: 560)
        .padding(24)
        .background(PadzyTheme.ground)
}

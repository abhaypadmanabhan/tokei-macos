import SwiftUI

/// Weekday × hour activity heatmap (WP-5, matches the mockup's `renderHeatmap`):
/// hand-rolled `Canvas` grid, 7 weekday rows × 24 hour columns, filled with a
/// single neutral hue whose OPACITY tracks intensity continuously
/// (`0.05 + t·0.85`) — a soft field, not stepped blocks. `nil`/zero cells render
/// at the faint floor. The honest empty state renders until a real hourly source
/// exists (Phase 1b gate — WP-1's `hourlyTotals`).
struct ActivityHeatmap: View {
    /// 7 rows (Mon…Sun) × 24 columns (hour 0…23); `nil` = no data for that cell.
    let matrix: [[Int?]]
    /// Copy under the empty-state headline (names the missing source).
    var emptyHint: String = "Hourly activity appears once local logs are parsed with per-hour timestamps."

    private static let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private static let hourLabels: [(column: Int, label: String)] = [
        (0, "12a"), (6, "6a"), (12, "12p"), (18, "6p"),
    ]

    private var hasData: Bool {
        matrix.contains { row in row.contains { ($0 ?? 0) > 0 } }
    }

    private var maxValue: Int {
        matrix.flatMap { $0 }.compactMap { $0 }.max() ?? 0
    }

    var body: some View {
        if matrix.count == 7, hasData {
            grid
        } else {
            emptyState
        }
    }

    private var grid: some View {
        let labelWidth: CGFloat = 30
        let rowGap: CGFloat = 2
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.weekdays, id: \.self) { day in
                        Text(day)
                            .font(.mono(size: 9))
                            .foregroundColor(PadzyTheme.ink5)
                            .frame(maxHeight: .infinity, alignment: .leading)
                    }
                }
                .frame(width: labelWidth)

                Canvas { context, size in
                    let columns = 24
                    let rows = 7
                    let gap: CGFloat = rowGap
                    let cellWidth = (size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
                    let cellHeight = (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
                    let peak = Double(max(maxValue, 1))

                    for row in 0..<rows {
                        for column in 0..<columns {
                            let rect = CGRect(
                                x: CGFloat(column) * (cellWidth + gap),
                                y: CGFloat(row) * (cellHeight + gap),
                                width: cellWidth,
                                height: cellHeight
                            )
                            let path = Path(roundedRect: rect, cornerRadius: 2)
                            let value = matrix.indices.contains(row) && matrix[row].indices.contains(column)
                                ? matrix[row][column]
                                : nil
                            // Single neutral hue, opacity tracks intensity continuously
                            // (mockup: 0.05 + t·0.85); nil/zero rest at the faint floor.
                            let intensity: Double
                            if let value, value > 0 {
                                intensity = min(1, Double(value) / peak)
                            } else {
                                intensity = 0
                            }
                            context.fill(path, with: .color(PadzyChartPalette.heatCell(intensity)))
                        }
                    }
                }
            }

            // Hour axis, aligned to the 24-column grid.
            GeometryReader { geo in
                let gridWidth = geo.size.width - labelWidth - 8
                let columnWidth = gridWidth / 24
                ZStack(alignment: .topLeading) {
                    ForEach(Self.hourLabels, id: \.column) { mark in
                        Text(mark.label)
                            .font(.mono(size: 9))
                            .foregroundColor(PadzyTheme.ink5)
                            .offset(x: labelWidth + 8 + CGFloat(mark.column) * columnWidth)
                    }
                }
            }
            .frame(height: 12)

            // "less → more" continuous gradient legend (mockup): a single-hue ramp
            // bar bracketed by muted labels, matching the neutral cell fill.
            HStack(spacing: 6) {
                Text("less")
                    .font(.mono(size: 9))
                    .foregroundColor(PadzyTheme.ink5)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(LinearGradient(
                        colors: [PadzyChartPalette.heatCell(0.0), PadzyChartPalette.heatCell(1.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: 96, height: 6)
                Text("more")
                    .font(.mono(size: 9))
                    .foregroundColor(PadzyTheme.ink5)
            }
            .padding(.top, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity heatmap by weekday and hour")
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
        .frame(width: 560, height: 190)
        .padding(24)
        .background(PadzyTheme.ground)
}

#Preview("Empty (Phase 1b gate)") {
    ActivityHeatmap(matrix: [])
        .frame(width: 560)
        .padding(24)
        .background(PadzyTheme.ground)
}

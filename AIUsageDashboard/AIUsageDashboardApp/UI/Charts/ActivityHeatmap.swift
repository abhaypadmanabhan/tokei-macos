import SwiftUI

/// One weekday × hour cell of the activity punch-card. `tint` is the colour of the
/// agent the user leaned on most that hour (DATA identity colour) — `nil` when the
/// hour is empty. `slotLabel` (weekday · hour) and `agentName` feed the styled hover
/// tooltip. Built by the Overview from the per-provider heatmaps.
struct HeatCell: Equatable {
    var total: Int
    var tint: Color?
    /// "Mon · 9a" — the weekday×hour category this cell represents (never a calendar
    /// day: cells aggregate that weekday+hour across the range).
    var slotLabel: String
    /// The agent worked most in this weekday×hour slot (`nil` when the slot is empty).
    var agentName: String?

    static let empty = HeatCell(total: 0, tint: nil, slotLabel: "", agentName: nil)
}

/// Weekday × hour activity punch-card, coloured by agent: each of the 7×24 square
/// cells takes the colour of the agent worked most that hour (orange = Claude,
/// green = Codex, …), and its brightness tracks how busy the hour was. Hover a
/// cell for the exact agent + token detail. A single scan tells you *when* you
/// work and *with what* — the same AgentTint identity colours used by the donut
/// and agent grid above, so the colours are already learnable.
///
/// Square cells at a fixed capped size (never stretched into wide rectangles),
/// 4 discrete brightness steps, and a visible empty box so the grid reads as
/// structure. Honest empty state until a real hourly source exists.
struct ActivityHeatmap: View {
    /// 7 rows (Mon…Sun) × 24 columns (hour 0…23).
    let cells: [[HeatCell]]

    var emptyHint: String = "Hourly activity appears once local logs are parsed with per-hour timestamps."

    @State private var width: CGFloat = 0
    /// The weekday×hour cell under the pointer (nil when not hovering a busy cell).
    @State private var hovered: HeatIndex?

    /// A weekday×hour cell address, for hover tracking.
    private struct HeatIndex: Equatable {
        let row: Int
        let column: Int
    }

    private static let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private static let hourMarks: [(column: Int, label: String)] = [
        (0, "12a"), (6, "6a"), (12, "12p"), (18, "6p"),
    ]

    private static let labelWidth: CGFloat = 28
    private static let labelGap: CGFloat = 8
    private static let gap: CGFloat = 2
    private static let minCell: CGFloat = 9
    private static let maxCell: CGFloat = 18
    private static let columns = 24
    private static let rows = 7

    private var hasData: Bool {
        cells.contains { row in row.contains { $0.total > 0 } }
    }

    private var maxValue: Int {
        cells.flatMap { $0 }.map(\.total).max() ?? 0
    }

    private var cell: CGFloat {
        let gridWidth = width - Self.labelWidth - Self.labelGap
        let raw = (gridWidth - Self.gap * CGFloat(Self.columns - 1)) / CGFloat(Self.columns)
        return min(Self.maxCell, max(Self.minCell, raw))
    }

    var body: some View {
        Group {
            if cells.count == Self.rows, hasData {
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
        let peak = Double(max(maxValue, 1))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: Self.labelGap) {
                VStack(spacing: Self.gap) {
                    ForEach(Self.weekdays, id: \.self) { day in
                        Text(day)
                            .font(.mono(size: 9))
                            .foregroundColor(PadzyTheme.ink5)
                            .frame(width: Self.labelWidth, height: cell, alignment: .leading)
                    }
                }

                VStack(spacing: Self.gap) {
                    ForEach(0..<Self.rows, id: \.self) { row in
                        HStack(spacing: Self.gap) {
                            ForEach(0..<Self.columns, id: \.self) { column in
                                cellView(at: row, column: column, peak: peak)
                            }
                        }
                    }
                }
            }

            hourAxis
            caption
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topLeading) { tooltipOverlay }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity heatmap by weekday and hour, coloured by the agent used most each hour")
    }

    /// Immediate styled hover tooltip (replaces the slow system `.help`): the
    /// weekday×hour slot, the agent worked most in it, and the slot's total tokens.
    /// Positioned next to the hovered cell; placed above for the lower rows so it
    /// never falls off the component. Non-interactive so it can't eat hover events.
    @ViewBuilder
    private var tooltipOverlay: some View {
        if let hovered,
           cells.indices.contains(hovered.row),
           cells[hovered.row].indices.contains(hovered.column),
           case let model = cells[hovered.row][hovered.column],
           model.total > 0 {
            heatTooltip(model)
                .frame(width: Self.tooltipWidth, alignment: .leading)
                .offset(tooltipOffset(hovered))
                .allowsHitTesting(false)
        }
    }

    private func heatTooltip(_ model: HeatCell) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.slotLabel)
                .font(.mono(size: 9))
                .tracking(0.3)
                .foregroundColor(PadzyTheme.ink5)
            Text(TokenFormatter.format(model.total))
                .font(.mono(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink)
            if let agent = model.agentName {
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.tint ?? PadzyTheme.ink4)
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
    }

    private static let tooltipWidth: CGFloat = 150
    private static let tooltipEstHeight: CGFloat = 46

    /// Offset from the grid's top-leading to sit the tooltip beside the hovered cell.
    /// Horizontally centred on the cell then clamped inside the width; placed below
    /// the cell for the top rows and above it for the lower rows.
    private func tooltipOffset(_ index: HeatIndex) -> CGSize {
        let cellSize = cell
        let cellX = Self.labelWidth + Self.labelGap + CGFloat(index.column) * (cellSize + Self.gap)
        let rawX = cellX + cellSize / 2 - Self.tooltipWidth / 2
        let maxX = max(0, width - Self.tooltipWidth)
        let x = min(max(0, rawX), maxX)

        let rowY = CGFloat(index.row) * (cellSize + Self.gap)
        let y = index.row >= 4
            ? max(0, rowY - Self.tooltipEstHeight - 4)
            : rowY + cellSize + 6
        return CGSize(width: x, height: y)
    }

    @ViewBuilder
    private func cellView(at row: Int, column: Int, peak: Double) -> some View {
        let model = cells.indices.contains(row) && cells[row].indices.contains(column)
            ? cells[row][column]
            : HeatCell.empty
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(cellColor(model, peak: peak))
            .frame(width: cell, height: cell)
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    hovered = model.total > 0 ? HeatIndex(row: row, column: column) : nil
                case .ended:
                    if hovered == HeatIndex(row: row, column: column) { hovered = nil }
                }
            }
    }

    /// Empty cells are a faint but visible box so the grid reads. Active cells take
    /// the dominant agent's tint, brightened in 4 discrete steps by how busy the
    /// hour was — with an opacity floor so the hue is always legible, never a wash.
    private func cellColor(_ model: HeatCell, peak: Double) -> Color {
        guard model.total > 0, let tint = model.tint else { return PadzyTheme.hairline }
        let intensity = min(1.0, Double(model.total) / peak)
        let step = Double(min(4, max(1, Int(ceil(intensity * 4))))) / 4.0
        return tint.opacity(0.4 + 0.6 * step)
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

    private var caption: some View {
        Text("Coloured by the agent you used most each hour · brighter = busier · hover for detail")
            .font(.mono(size: 9))
            .foregroundColor(PadzyTheme.ink5)
            .padding(.top, 2)
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

private func sampleCells() -> [[HeatCell]] {
    let tints: [Color] = [AgentTint.color(.claudeCode), AgentTint.color(.codex),
                          AgentTint.color(.cursor), AgentTint.color(.cline)]
    let names = ["Claude Code", "Codex", "Cursor", "Cline"]
    return (0..<7).map { row in
        (0..<24).map { hour -> HeatCell in
            guard hour >= 7, hour <= 23 else { return .empty }
            let weekend = row >= 5
            let midday = hour >= 9 && hour <= 18 ? 8 : 2
            let total = (weekend ? 1 : midday) * ((row + hour) % 4 + 1) * 1_000_000
            guard total > 0 else { return .empty }
            let idx = (row + hour) % tints.count
            return HeatCell(total: total, tint: tints[idx],
                            slotLabel: "\(ActivityHeatmap.previewDay(row)) · \(hour):00",
                            agentName: names[idx])
        }
    }
}

extension ActivityHeatmap {
    static func previewDay(_ row: Int) -> String { weekdays[row] }
}

#Preview("Full week · agent-coloured") {
    ActivityHeatmap(cells: sampleCells())
        .frame(width: 560)
        .padding(24)
        .background(PadzyTheme.ground)
}

#Preview("Narrow 640") {
    ActivityHeatmap(cells: sampleCells())
        .frame(width: 420)
        .padding(24)
        .background(PadzyTheme.ground)
}

#Preview("Empty") {
    ActivityHeatmap(cells: [])
        .frame(width: 560)
        .padding(24)
        .background(PadzyTheme.ground)
}

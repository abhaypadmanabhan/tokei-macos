import SwiftUI
import AIUsageDashboardCore

/// One resolved agent cell for the Overview grid: identity + the stat the mockup
/// shows for the active lens (Usage → today tokens; Quota → used% + a `% left`
/// substat / an honest connect state), its ink level, whether the number is an
/// estimate (dotted underline), and whether this agent carries the single "most
/// headroom" dot.
struct AgentCellModel: Identifiable {
    let providerID: ProviderID
    let name: String
    let stat: String
    let statColor: Color
    /// Secondary line under the stat — the Quota lens's "54% left" / "FETCHING…" /
    /// "ENABLE →" / "LOCAL LOGS" caption. `nil` in the Usage lens.
    var substat: String? = nil
    var substatColor: Color = PadzyTheme.ink5
    /// Estimated today tokens → subtle dotted underline + a `.help` tooltip.
    let isEstimated: Bool
    /// The single emptiest quota-bearing agent → a green "route here" dot.
    let hasHeadroom: Bool

    var id: ProviderID { providerID }
}

/// The mockup's 1px-gap agent grid: window-coloured cells over a hairline backing,
/// so the 1px gaps and the outer rounded border read as crisp hairlines. Column
/// count comes from measured width (reflow: 4 → 3 → 2 → 1). A partial last row is
/// padded with window-coloured fillers so the backing never shows as a dark block.
struct AgentGrid: View {
    let models: [AgentCellModel]
    let onSelect: (ProviderID) -> Void

    @State private var width: CGFloat = 0

    private var columns: Int {
        switch width {
        case 720...: return 4
        case 520..<720: return 3
        case 340..<520: return 2
        default: return max(1, min(2, models.count))
        }
    }

    var body: some View {
        let cols = columns
        let rows = stride(from: 0, to: models.count, by: cols).map { start in
            Array(models[start..<min(start + cols, models.count)])
        }

        VStack(spacing: 1) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 1) {
                    ForEach(0..<cols, id: \.self) { columnIndex in
                        if columnIndex < rows[rowIndex].count {
                            AgentGridCell(model: rows[rowIndex][columnIndex], onSelect: onSelect)
                        } else {
                            // Filler keeps the last row window-coloured, not hairline.
                            Rectangle().fill(PadzyTheme.window)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(PadzyTheme.hairline)
        .clipShape(RoundedRectangle(cornerRadius: PadzyRadius.cell, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PadzyRadius.cell, style: .continuous)
                .stroke(PadzyTheme.hairline, lineWidth: 1)
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: OverviewWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(OverviewWidthKey.self) { width = $0 }
    }
}

/// A single agent cell — a button into the provider drill-in. Tinted mark + name,
/// then the stat, with the optional headroom dot top-right and the optional dotted
/// confidence underline on the number.
struct AgentGridCell: View {
    let model: AgentCellModel
    let onSelect: (ProviderID) -> Void

    var body: some View {
        Button {
            onSelect(model.providerID)
        } label: {
            VStack(alignment: .leading, spacing: PadzySpace.m) {
                HStack(alignment: .top, spacing: PadzySpace.s) {
                    ProviderBrandMark.tinted(model.providerID, size: 20)
                    Text(model.name)
                        .font(.sans(size: 12, weight: .medium))
                        .foregroundColor(PadzyTheme.ink2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    if model.hasHeadroom {
                        Circle()
                            .fill(PadzyTheme.good)
                            .frame(width: 6, height: 6)
                            .help("Most headroom — route new work here")
                            .accessibilityLabel("Most headroom, route new work here")
                    }
                }
                stat
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background(PadzyTheme.window)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(model.name), \(model.stat)\(model.isEstimated ? ", estimated" : "")")
        .accessibilityHint("Opens \(model.name) detail")
    }

    @ViewBuilder
    private var stat: some View {
        VStack(alignment: .leading, spacing: 3) {
            if model.isEstimated {
                Text(model.stat)
                    .font(.mono(size: 18, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(model.statColor)
                DottedUnderline()
                    .fixedSize()
                    .help("Estimated — not directly reported")
            } else {
                Text(model.stat)
                    .font(.mono(size: 18, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(model.statColor)
            }

            if let substat = model.substat {
                Text(substat)
                    .font(.mono(size: 10))
                    .tracking(0.2)
                    .monospacedDigit()
                    .foregroundColor(model.substatColor)
                    .lineLimit(1)
            }
        }
    }
}

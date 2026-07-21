import SwiftUI
import Charts
import AIUsageDashboardCore

/// Usage-by-provider donut (WP-5 mockup): Swift Charts `SectorMark` slices coloured
/// by each agent's `AgentTint` (identity colour, DATA — never the product accent or
/// the legacy pink ramp), total in the center, external legend rows carrying
/// tint · name · absolute · %. Plain value inputs; slices ordered largest-first.
/// Honest empty state when every share is zero.
struct ProviderDonut: View {
    let slices: [(provider: ProviderID, tokens: Int)]

    private struct Slice: Identifiable {
        let id: String
        let name: String
        let tokens: Int
        let share: Double
        let color: Color
    }

    private var resolved: [Slice] {
        let positive = slices.filter { $0.tokens > 0 }.sorted { $0.tokens > $1.tokens }
        let total = positive.reduce(0) { $0 + $1.tokens }
        guard total > 0 else { return [] }
        return positive.map { slice in
            Slice(
                id: slice.provider.rawValue,
                name: displayName(slice.provider),
                tokens: slice.tokens,
                share: Double(slice.tokens) / Double(total) * 100,
                color: AgentTint.color(slice.provider)
            )
        }
    }

    private var total: Int { slices.reduce(0) { $0 + max(0, $1.tokens) } }

    private func displayName(_ id: ProviderID) -> String {
        switch id {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .antigravity: return "Antigravity"
        case .cline: return "Cline"
        case .opencode: return "opencode"
        case .gemini: return "Gemini"
        }
    }

    var body: some View {
        let resolved = resolved
        if resolved.isEmpty {
            emptyState
        } else {
            HStack(alignment: .center, spacing: 20) {
                donut(resolved)
                    .frame(width: 150, height: 150)
                legend(resolved)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func donut(_ resolved: [Slice]) -> some View {
        Chart(resolved) { slice in
            SectorMark(
                angle: .value("Tokens", slice.tokens),
                innerRadius: .ratio(0.68),
                angularInset: 1.5
            )
            .cornerRadius(2)
            .foregroundStyle(slice.color)
        }
        .chartLegend(.hidden)
        .chartBackground { _ in
            VStack(spacing: 2) {
                Text(TokenFormatter.format(total))
                    .font(.mono(size: 20))
                    .monospacedDigit()
                    .foregroundColor(PadzyTheme.ink)
                Text("TOTAL")
                    .font(.mono(size: 9))
                    .tracking(9 * 0.08)
                    .foregroundColor(PadzyTheme.muted)
            }
        }
    }

    private func legend(_ resolved: [Slice]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(resolved) { slice in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(slice.color)
                        .frame(width: 8, height: 8)
                    Text(slice.name.uppercased())
                        .font(.mono(size: 10))
                        .foregroundColor(PadzyTheme.ink2)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(TokenFormatter.format(slice.tokens))
                        .font(.mono(size: 10))
                        .monospacedDigit()
                        .foregroundColor(PadzyTheme.ink)
                        .frame(width: 52, alignment: .trailing)
                    Text("\(Int(round(slice.share)))%")
                        .font(.mono(size: 10))
                        .monospacedDigit()
                        .foregroundColor(PadzyTheme.ink4)
                        .frame(width: 34, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(slice.name), \(Int(round(slice.share))) percent, \(TokenFormatter.format(slice.tokens)) tokens")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                .fill(PadzyTheme.ground.opacity(0.4))
            Text("NO USAGE RECORDED")
                .font(.mono(size: 11))
                .tracking(11 * 0.08)
                .foregroundColor(PadzyTheme.muted)
        }
        .frame(height: 150)
    }
}

// MARK: - Previews

#Preview("Full split") {
    ProviderDonut(slices: [
        (provider: .claudeCode, tokens: 131_000_000),
        (provider: .codex, tokens: 48_200_000),
        (provider: .cursor, tokens: 21_700_000),
        (provider: .opencode, tokens: 9_400_000),
        (provider: .cline, tokens: 2_100_000),
    ])
    .padding(24)
    .frame(width: 460)
    .background(PadzyTheme.ground)
}

#Preview("Two providers") {
    ProviderDonut(slices: [
        (provider: .claudeCode, tokens: 89_000_000),
        (provider: .codex, tokens: 23_000_000),
    ])
    .padding(24)
    .frame(width: 460)
    .background(PadzyTheme.ground)
}

#Preview("Empty") {
    ProviderDonut(slices: [(provider: .claudeCode, tokens: 0)])
        .padding(24)
        .frame(width: 460)
        .background(PadzyTheme.ground)
}

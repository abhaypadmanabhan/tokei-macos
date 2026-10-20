import SwiftUI
import AIUsageDashboardCore

/// One model's month-to-date value as the plain values the drill-in renders. Mapped from
/// `MaxxerModelValue` at the edge so the view (and its previews) never need Core to build one.
struct ModelValueRow: Identifiable, Equatable {
    let model: String
    let tokens: Int
    /// `nil` when the model has no public rate: counted, never priced with a guess.
    let apiEquivalentUSD: Double?

    var id: String { model }

    init(model: String, tokens: Int, apiEquivalentUSD: Double?) {
        self.model = model
        self.tokens = tokens
        self.apiEquivalentUSD = apiEquivalentUSD
    }

    init(_ value: MaxxerModelValue) {
        self.init(model: value.model, tokens: value.totalTokens, apiEquivalentUSD: value.apiEquivalentUSD)
    }
}

/// "Value by model, this month": which models the month's API-equivalent value came
/// from, largest first as the engine orders them. Unpriced rows stay in the list with
/// their tokens and say so, rather than vanishing or borrowing a neighbour's rate.
/// The caller hides the section when there are no rows.
struct ModelValueSection: View {
    let rows: [ModelValueRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Value by model, this month")
                .font(.sans(size: 15, weight: .semibold))
                .foregroundColor(PadzyTheme.ink2)
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    HairlineDivider()
                    rowView(row)
                }
                HairlineDivider()
            }
            if rows.contains(where: { $0.apiEquivalentUSD == nil }) {
                Text("No public rate: those tokens are counted, never priced with a guess.")
                    .font(.sans(size: 15))
                    .foregroundColor(PadzyTheme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func rowView(_ row: ModelValueRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(row.model)
                .font(.mono(size: 15))
                .foregroundColor(PadzyTheme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(row.model)
            Spacer(minLength: 12)
            Text(TokenFormatter.format(row.tokens))
                .font(.mono(size: 15))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink3)
                .fixedSize()
            Group {
                if let usd = row.apiEquivalentUSD {
                    Text(MaxxerMath.formatUSD(usd))
                        .font(.mono(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(PadzyTheme.ink)
                } else {
                    Text("no public rate")
                        .font(.sans(size: 15))
                        .foregroundColor(PadzyTheme.ink3)
                }
            }
            .frame(minWidth: 104, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(row))
    }

    private func accessibilityLabel(_ row: ModelValueRow) -> String {
        let value = row.apiEquivalentUSD.map { "worth \(MaxxerMath.formatUSD($0)) at API rates" }
            ?? "no public rate"
        return "\(row.model), \(TokenFormatter.format(row.tokens)) tokens this month, \(value)"
    }
}

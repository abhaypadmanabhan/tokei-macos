import SwiftUI
import AIUsageDashboardCore

struct QuotaWindowRow: View {
    let window: QuotaWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window.type.rawValue.uppercased())
                    .font(.display(size: 11, weight: .bold))
                    .foregroundColor(PadzyTheme.ink)

                Spacer()

                HStack(spacing: 6) {
                    if let used = window.used {
                        Text(TokenFormatter.format(Int(used)))
                            .font(.mono(size: 11))
                            .foregroundColor(PadzyTheme.ink)
                    }
                    if let limit = window.limit {
                        Text("/ \(TokenFormatter.format(Int(limit)))")
                            .font(.mono(size: 11))
                            .foregroundColor(PadzyTheme.muted)
                    }
                    ConfidenceBadge(confidence: window.confidence)
                }
            }

            if !window.source.isEmpty {
                Text(window.source)
                    .font(.mono(size: 10))
                    .foregroundColor(PadzyTheme.muted)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }
}

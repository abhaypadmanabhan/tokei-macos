import SwiftUI
import AIUsageDashboardCore

struct QuotaWindowRow: View {
    let window: QuotaWindow

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(window.type.rawValue.capitalized)
                    .font(.subheadline.bold())
                if !window.source.isEmpty {
                    Text(window.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                if let used = window.used {
                    Text("\(Int(used)) used")
                        .font(.caption)
                        .monospacedDigit()
                }
                if let limit = window.limit {
                    Text("/ \(Int(limit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ConfidenceBadge(confidence: window.confidence)
            }
        }
        .padding(.vertical, 2)
    }
}


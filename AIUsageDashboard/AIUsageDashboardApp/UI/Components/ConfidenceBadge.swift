import SwiftUI
import AIUsageDashboardCore

struct ConfidenceBadge: View {
    let confidence: MetricConfidence
    /// Abbreviated form for dense tables where the full `displayName`
    /// ("Provider Reported") would blow the column width. Additive — existing
    /// callers keep the long label.
    var compact: Bool = false

    /// Short forms chosen to stay unambiguous at a glance: never abbreviate two
    /// different confidences to the same prefix.
    private var label: String {
        guard compact else { return confidence.displayName.uppercased() }
        switch confidence {
        case .exact: return "EXACT"
        case .providerReported: return "REPORTED"
        case .localParsed: return "PARSED"
        case .estimated: return "EST"
        case .unavailable: return "N/A"
        }
    }

    var body: some View {
        Text(label)
            .font(.mono(size: 9))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundColor(PadzyTheme.ink)
            .background(Color.clear)
            .border(PadzyTheme.muted, width: 1)
            .accessibilityLabel("Confidence: \(confidence.displayName)")
    }
}


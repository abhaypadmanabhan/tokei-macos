import SwiftUI
import AIUsageDashboardCore

struct ConfidenceBadge: View {
    let confidence: MetricConfidence
    /// Abbreviated form for dense tables where the full `displayName`
    /// ("Provider Reported") would blow the column width. Additive — existing
    /// callers keep the long label.
    var compact: Bool = false

    /// Where the number came from, as a short sentence-case word (no badge box, no capitals:
    /// Tokei has no eyebrow labels). The compact form is shorter, never ambiguous.
    private var label: String {
        switch confidence {
        case .exact: return "Exact"
        case .providerReported: return compact ? "Reported" : "Reported by the provider"
        case .localParsed: return "Local logs"
        case .estimated: return compact ? "Estimate" : "Estimated"
        case .unavailable: return "Unavailable"
        }
    }

    var body: some View {
        Text(label)
            .font(.sans(size: 12))
            .foregroundColor(PadzyTheme.ink3)
            .accessibilityLabel("Confidence: \(confidence.displayName)")
    }
}


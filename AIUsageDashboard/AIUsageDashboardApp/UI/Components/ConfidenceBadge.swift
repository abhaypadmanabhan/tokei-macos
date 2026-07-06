import SwiftUI
import AIUsageDashboardCore

struct ConfidenceBadge: View {
    let confidence: MetricConfidence

    var body: some View {
        Text(confidence.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch confidence {
        case .exact: return .green
        case .providerReported: return .blue
        case .localParsed: return .purple
        case .estimated: return .orange
        case .unavailable: return .secondary
        }
    }
}


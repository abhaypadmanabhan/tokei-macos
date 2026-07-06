import SwiftUI
import AIUsageDashboardCore

struct ConfidenceBadge: View {
    let confidence: MetricConfidence

    var body: some View {
        Text(confidence.displayName.uppercased())
            .font(.mono(size: 9))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundColor(PadzyTheme.ink)
            .background(Color.clear)
            .border(PadzyTheme.muted, width: 1)
    }
}


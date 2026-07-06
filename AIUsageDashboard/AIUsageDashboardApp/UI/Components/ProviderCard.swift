import SwiftUI
import AIUsageDashboardCore

struct ProviderCard: View {
    let snapshot: ProviderSnapshot

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.displayName)
                    .font(.headline)
                Text("Today: \(snapshot.todayUsage.totalTokens ?? 0) tokens")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ConfidenceBadge(confidence: snapshot.todayUsage.confidence)
        }
        .padding(.vertical, 4)
    }
}


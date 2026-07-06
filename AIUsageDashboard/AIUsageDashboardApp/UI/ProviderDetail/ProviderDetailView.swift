import SwiftUI
import AIUsageDashboardCore

struct ProviderDetailView: View {
    let snapshot: ProviderSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(snapshot.displayName)
                        .font(.largeTitle)
                    Spacer()
                    ConfidenceBadge(confidence: snapshot.todayUsage.confidence)
                }

                Text("Auth status: \(snapshot.authStatus.rawValue)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !snapshot.quotaWindows.isEmpty {
                    Section(header: Text("Quota Windows").font(.headline)) {
                        ForEach(snapshot.quotaWindows) { window in
                            QuotaWindowRow(window: window)
                        }
                    }
                }

                Section(header: Text("Usage").font(.headline)) {
                    UsageRow(title: "Today", usage: snapshot.todayUsage)
                    UsageRow(title: "This Week", usage: snapshot.weekUsage)
                    if let month = snapshot.monthUsage { UsageRow(title: "This Month", usage: month) }
                    if let lifetime = snapshot.lifetimeUsage { UsageRow(title: "Lifetime", usage: lifetime) }
                }

                if !snapshot.warnings.isEmpty {
                    Section(header: Text("Warnings").font(.headline)) {
                        ForEach(snapshot.warnings) { warning in
                            Text(warning.message)
                                .font(.caption)
                                .foregroundStyle(warning.level == .error ? .red : .orange)
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

private struct UsageRow: View {
    let title: String
    let usage: TokenUsage

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(usage.totalTokens ?? 0) tokens")
                .monospacedDigit()
            ConfidenceBadge(confidence: usage.confidence)
        }
    }
}


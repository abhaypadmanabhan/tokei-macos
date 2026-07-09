import SwiftUI
import AIUsageDashboardCore

struct ProviderDetailView: View {
    let snapshot: ProviderSnapshot

    private var tier: ProviderCapabilityTier {
        ProviderCapabilityTier.classify(snapshot)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionLabel("Detail")

                Text(snapshot.displayName.uppercased())
                    .font(.display(size: 20, weight: .black))
                    .foregroundColor(PadzyTheme.ink)

                Text("\(tier.label)  ·  \(ProviderMetadata.localPaths(for: snapshot.providerID).joined(separator: ", "))")
                    .font(.mono(size: 10))
                    .foregroundColor(PadzyTheme.muted)

                HairlineDivider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("TODAY")
                        .font(.mono(size: 11))
                        .foregroundColor(PadzyTheme.muted)
                    Text(TokenFormatter.format(snapshot.todayUsage.totalTokens))
                        .font(.mono(size: 18))
                        .foregroundColor(PadzyTheme.ink)
                }
                .padding(12)
                .background(PadzyTheme.surface)
                .border(PadzyTheme.muted.opacity(0.3), width: 1)

                if let plan = ProviderMetadata.planText(from: snapshot.warnings) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PLAN")
                            .font(.mono(size: 11))
                            .foregroundColor(PadzyTheme.muted)
                        Text(plan.uppercased())
                            .font(.mono(size: 18))
                            .foregroundColor(PadzyTheme.ink)
                    }
                    .padding(12)
                    .background(PadzyTheme.surface)
                    .border(PadzyTheme.muted.opacity(0.3), width: 1)
                }

                if let creditsWindow = snapshot.quotaWindows.first(where: { $0.type == .credits }) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CREDITS")
                            .font(.mono(size: 11))
                            .foregroundColor(PadzyTheme.muted)
                        Text(creditsWindow.remaining.map { "\(Int($0)) REMAINING" } ?? "UNAVAILABLE")
                            .font(.mono(size: 18))
                            .foregroundColor(PadzyTheme.ink)
                    }
                    .padding(12)
                    .background(PadzyTheme.surface)
                    .border(PadzyTheme.muted.opacity(0.3), width: 1)
                }
            }
            .padding(20)
        }
        .background(PadzyTheme.ground)
    }
}

import SwiftUI
import AIUsageDashboardCore

struct ProviderDetailView: View {
    let snapshot: ProviderSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                EditorialKicker(number: "02", title: "DETAIL")
                
                Text(snapshot.displayName.uppercased())
                    .font(.display(size: 20, weight: .black))
                    .foregroundColor(PadzyTheme.ink)
                
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
            }
            .padding(20)
        }
        .background(PadzyTheme.ground)
    }
}

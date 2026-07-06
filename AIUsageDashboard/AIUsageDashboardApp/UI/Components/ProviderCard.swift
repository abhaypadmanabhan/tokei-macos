import SwiftUI
import AIUsageDashboardCore

struct ProviderCard: View {
    let providerID: ProviderID
    let displayName: String
    let todayUsage: TokenUsage?
    let isSelected: Bool
    let isAvailable: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Accent Tick (square 2px accent bar on leading edge)
            if isSelected {
                Rectangle()
                    .fill(PadzyTheme.accent)
                    .frame(width: 2)
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 2)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName.uppercased())
                        .font(.display(size: 13, weight: .bold))
                        .foregroundColor(isAvailable ? PadzyTheme.ink : PadzyTheme.muted)

                    if isAvailable, let usage = todayUsage {
                        Text("TODAY: \(TokenFormatter.format(usage.totalTokens))")
                            .font(.mono(size: 11))
                            .foregroundColor(PadzyTheme.muted)
                    } else {
                        Text("UNAVAILABLE")
                            .font(.mono(size: 11))
                            .foregroundColor(PadzyTheme.muted)
                    }
                }
                Spacer()

                if isAvailable, let usage = todayUsage {
                    ConfidenceBadge(confidence: usage.confidence)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(isSelected ? PadzyTheme.surface : (isHovered && isAvailable ? PadzyTheme.surface.opacity(0.5) : Color.clear))
        .onHover { hovering in
            if isAvailable {
                isHovered = hovering
            }
        }
    }
}

import SwiftUI
import AIUsageDashboardCore

struct ProviderCard: View {
    let providerID: ProviderID
    let displayName: String
    let todayUsage: TokenUsage?
    let tier: ProviderCapabilityTier
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

            HStack(spacing: 10) {
                if isAvailable {
                    ProviderBrandMark(providerID, size: 22)
                } else {
                    ProviderMark(providerID, size: 18, enabled: false)
                        .frame(width: 22, height: 22)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName.uppercased())
                        .font(.display(size: 13, weight: .bold))
                        .foregroundColor(isAvailable ? PadzyTheme.ink : PadzyTheme.muted)

                    if !isAvailable {
                        Text("UNAVAILABLE")
                            .font(.mono(size: 11))
                            .foregroundColor(PadzyTheme.muted)
                    } else if tier == .fullMetrics, let usage = todayUsage {
                        Text("TODAY: \(TokenFormatter.format(usage.totalTokens))")
                            .font(.mono(size: 11))
                            .foregroundColor(PadzyTheme.muted)
                    } else {
                        // Honest label for a provider that is installed/detected but
                        // has no token-usage signal yet — never reads as broken.
                        Text(tier.label)
                            .font(.mono(size: 11))
                            .foregroundColor(PadzyTheme.muted)
                    }
                }
                Spacer()

                if isAvailable, tier == .fullMetrics, let usage = todayUsage {
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

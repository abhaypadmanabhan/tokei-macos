import SwiftUI
import AIUsageDashboardCore

/// Provider mark for the redesigned surfaces: the monochrome `ProviderMark`
/// template glyph (ink) on a neutral hairline chip. One monochrome family —
/// brand hues clashed with the UI, so no per-provider color and no color
/// assets are consulted. Sizes are the chip's outer edge, matching the old
/// colored-mark footprint at every call site.
struct ProviderBrandMark: View {
    let providerID: ProviderID
    var size: CGFloat = 28

    init(_ providerID: ProviderID, size: CGFloat = 28) {
        self.providerID = providerID
        self.size = size
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: max(4, size * 0.28), style: .continuous)
                .fill(PadzyTheme.ink.opacity(0.06))
            RoundedRectangle(cornerRadius: max(4, size * 0.28), style: .continuous)
                .stroke(PadzyTheme.muted.opacity(0.35), lineWidth: 1)
            ProviderMark(providerID, size: size * 0.58)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview("Monochrome marks") {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            ForEach(ProviderID.allCases, id: \.self) { ProviderBrandMark($0, size: 34) }
        }
        HStack(spacing: 16) {
            ForEach(ProviderID.allCases, id: \.self) { ProviderBrandMark($0, size: 22) }
        }
        HStack(spacing: 16) {
            ForEach(ProviderID.allCases, id: \.self) { ProviderMark($0, size: 22, enabled: false) }
        }
    }
    .padding(32)
    .background(PadzyTheme.ground)
}

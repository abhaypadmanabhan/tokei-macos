import SwiftUI
import AIUsageDashboardCore

/// Colored per-provider brand mark for the redesigned surfaces (design spec §3).
/// Resolution order — nothing ever renders blank:
/// 1. A full-color asset in `Assets.xcassets/ProviderBrands/brand_<provider>`
///    (drop-in slots ship empty until licensed/crafted art lands).
/// 2. Fallback: the existing monochrome `ProviderMark` template glyph, tinted in
///    the provider's brand hue on a rounded surface chip.
/// The monochrome `ProviderMark` remains the mark for dense/menu-bar contexts.
struct ProviderBrandMark: View {
    let providerID: ProviderID
    var size: CGFloat = 28

    init(_ providerID: ProviderID, size: CGFloat = 28) {
        self.providerID = providerID
        self.size = size
    }

    private var assetName: String {
        switch providerID {
        case .claudeCode: return "brand_claude"
        case .codex: return "brand_codex"
        case .cursor: return "brand_cursor"
        case .antigravity: return "brand_antigravity"
        case .cline: return "brand_cline"
        case .opencode: return "brand_opencode"
        }
    }

    /// Decorative identity hue for the fallback chip (approximates each brand).
    /// Data/chrome color rules don't apply to brand identity marks.
    static func brandColor(for providerID: ProviderID) -> Color {
        switch providerID {
        case .claudeCode: return Color(hex: "D97757")
        case .codex: return Color(hex: "10A37F")
        case .cursor: return Color(hex: "ECECF1")
        case .antigravity: return Color(hex: "4C8DF6")
        case .cline: return Color(hex: "9D7CD8")
        case .opencode: return Color(hex: "A8A8B0")
        }
    }

    var body: some View {
        Group {
            if let nsImage = NSImage(named: assetName), nsImage.isValid, !nsImage.representations.isEmpty {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                fallbackChip
            }
        }
        .accessibilityHidden(true)
    }

    private var fallbackChip: some View {
        let brand = Self.brandColor(for: providerID)
        return ZStack {
            RoundedRectangle(cornerRadius: max(4, size * 0.28), style: .continuous)
                .fill(brand.opacity(0.14))
            RoundedRectangle(cornerRadius: max(4, size * 0.28), style: .continuous)
                .stroke(brand.opacity(0.35), lineWidth: 1)
            ProviderMark(providerID, size: size * 0.58)
                .foregroundColor(brand)
                .colorMultiply(brand)
        }
        .frame(width: size, height: size)
    }
}

#Preview("Brand marks (fallback chips)") {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            ForEach(ProviderID.allCases, id: \.self) { ProviderBrandMark($0, size: 34) }
        }
        HStack(spacing: 16) {
            ForEach(ProviderID.allCases, id: \.self) { ProviderBrandMark($0, size: 22) }
        }
    }
    .padding(32)
    .background(PadzyTheme.ground)
}

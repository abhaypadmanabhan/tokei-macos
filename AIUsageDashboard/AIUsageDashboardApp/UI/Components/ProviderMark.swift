import SwiftUI
import AIUsageDashboardCore

/// Monochrome provider glyph rendered as a **template** image, tinted with the
/// active PadzyTheme ink (enabled) or muted (disabled). Assets live in
/// `Assets.xcassets/ProviderMarks/*` as single-shape vector PDFs with
/// `template-rendering-intent = template`. If an asset is missing we fall back
/// to an SF Symbol so a mark is never blank.
struct ProviderMark: View {
    let providerID: ProviderID
    var size: CGFloat = 18
    var enabled: Bool = true

    init(_ providerID: ProviderID, size: CGFloat = 18, enabled: Bool = true) {
        self.providerID = providerID
        self.size = size
        self.enabled = enabled
    }

    private var assetName: String {
        switch providerID {
        case .claudeCode: return "mark_claude"
        case .codex: return "mark_codex"
        case .cursor: return "mark_cursor"
        case .antigravity: return "mark_antigravity"
        case .cline: return "mark_cline"
        }
    }

    var body: some View {
        Group {
            if let nsImage = NSImage(named: assetName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .renderingMode(.template)
            } else {
                // Fallback — never leaves a blank slot if the asset is absent.
                Image(systemName: "cube")
                    .resizable()
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .foregroundColor(enabled ? PadzyTheme.ink : PadzyTheme.muted)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 24) {
        HStack(spacing: 16) {
            ForEach(ProviderID.allCases, id: \.self) { ProviderMark($0, size: 28) }
        }
        HStack(spacing: 16) {
            ForEach(ProviderID.allCases, id: \.self) { ProviderMark($0, size: 28, enabled: false) }
        }
    }
    .padding(32)
    .background(PadzyTheme.ground)
}

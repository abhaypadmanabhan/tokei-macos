import SwiftUI
import AIUsageDashboardCore

/// Per-agent identity colour (WP-5). These are low-chroma, restrained tints used
/// for DATA and identity only: chart series, the usage-split donut, per-agent
/// daily history, and the tinted glyph container. The single product
/// `PadzyTheme.accent` still owns every active/progress/primary STATE — an agent
/// tint never signals selection or action.
///
/// Reintroduces per-agent colour that WP-4 had removed; kept deliberately muted so
/// seven of them can coexist without the "brand-hue clash" that motivated the
/// removal. Sourced from the Tokei Dashboard mockup.
public enum AgentTint {
    public static func color(_ id: ProviderID) -> Color {
        switch id {
        case .claudeCode:  return Color(hex: "C77D5A")
        case .codex:       return Color(hex: "5FA88C")
        case .cursor:      return Color(hex: "9AA0AA")
        case .cline:       return Color(hex: "8A93E6")
        case .antigravity: return Color(hex: "D2A15C")
        case .gemini:      return Color(hex: "6D93DB")
        case .opencode:    return Color(hex: "B98BD0")
        }
    }
}

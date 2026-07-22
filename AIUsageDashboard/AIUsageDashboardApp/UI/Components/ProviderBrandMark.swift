import SwiftUI
import AIUsageDashboardCore

/// Provider glyph container for the redesigned surfaces: the `ProviderMark`
/// template glyph in a tight rounded-square chip.
///
/// WP-5: pass `tint` (an `AgentTint`) for the mockup's per-agent treatment — a
/// faint tinted fill, a stronger tinted border, and a tinted mark. Omit `tint`
/// to keep the monochrome ink-on-hairline chip for legacy call sites. The single
/// product accent is never used here; the tint is DATA/identity colour.
struct ProviderBrandMark: View {
    let providerID: ProviderID
    var size: CGFloat = 28
    var tint: Color? = nil

    init(_ providerID: ProviderID, size: CGFloat = 28, tint: Color? = nil) {
        self.providerID = providerID
        self.size = size
        self.tint = tint
    }

    private var radius: CGFloat { size >= 32 ? 4 : 3 }
    private var fill: Color { (tint ?? PadzyTheme.ink).opacity(tint == nil ? 0.06 : 0.08) }
    private var stroke: Color { tint?.opacity(0.33) ?? PadzyTheme.muted.opacity(0.35) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(stroke, lineWidth: 1)
            ProviderMark(providerID, size: size * 0.58, tint: tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Convenience: the tinted glyph for a provider using its `AgentTint`.
extension ProviderBrandMark {
    static func tinted(_ id: ProviderID, size: CGFloat = 28) -> ProviderBrandMark {
        ProviderBrandMark(id, size: size, tint: AgentTint.color(id))
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

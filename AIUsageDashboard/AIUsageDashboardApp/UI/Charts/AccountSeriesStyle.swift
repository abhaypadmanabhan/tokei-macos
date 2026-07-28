import SwiftUI

/// Series styling for N accounts of one provider. The provider's own tint leads (this is
/// still Claude's data), then a neutral ink, then a dimmed tint — with a dash pattern on top,
/// so two series are never told apart by hue alone.
///
/// Its own file, and free of any dependency beyond the theme tokens, so the
/// **no two series look alike** rule is unit-tested by the standard
/// `-scheme AIUsageDashboardCore test` run rather than argued about — see
/// `AccountSeriesStyleTests`. A chart whose lines collide answers the one question it exists
/// to answer with "you cannot tell", which is worse than not drawing it.
enum AccountSeriesStyle {
    /// 3 colours, 4 dashes. The counts are **coprime on purpose**: the pair `(index % 3,
    /// index % 4)` is unique for twelve consecutive accounts, where cycling both on the same
    /// modulus made account 3 byte-identical to account 0 in both channels — two solid orange
    /// lines crossing, with two identical legend swatches under them.
    private static let colorCount = 3
    private static let dashCount = 4

    static func color(_ index: Int, tint: Color) -> Color {
        switch index % colorCount {
        case 0: return tint
        case 1: return PadzyTheme.ink2
        default: return tint.opacity(0.55)
        }
    }

    static func dash(_ index: Int) -> [CGFloat] {
        switch index % dashCount {
        case 0: return []
        case 1: return [5, 3]
        case 2: return [2, 3]
        default: return [7, 3, 2, 3]
        }
    }
}

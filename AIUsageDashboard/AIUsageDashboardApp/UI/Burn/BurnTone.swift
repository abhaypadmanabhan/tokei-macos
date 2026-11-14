import SwiftUI

/// The burn surfaces' ink roles. The theme's `ink4` (#6E6E78) and `ink5` (#54545C) measure about
/// 3.9:1 and 2.6:1 on the ground, under the 4.5:1 floor for small text (docs/07-padzy-theme.md),
/// so burn text stops at `ink3` (about 7:1) and the two faint inks only draw marks: icons, bars,
/// tracks, which need 3:1. `BurnContrastTests` measures both and scans `UI/Burn` for strays.
enum BurnTone {
    /// The quietest text on a burn surface.
    static let caption = PadzyTheme.ink3
    /// Non-text marks: icons, bar fills, a locked badge's glyph.
    static let mark = PadzyTheme.ink4
}

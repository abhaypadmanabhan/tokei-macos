import SwiftUI
import XCTest

/// The per-account chart's promise is that you can tell the lines apart. Colour alone does
/// not carry that (hue-blind readers, and a printed or screenshotted chart), so every series
/// must differ from every other in colour **or** dash — and the legend swatch below the chart
/// draws the same pair, so a collision there is a collision everywhere.
///
/// Four accounts is not hypothetical: `CLAUDE_CONFIG_DIR` has no limit, and the whole point of
/// this surface is deciding which account to route work to.
final class AccountSeriesStyleTests: XCTestCase {
    private let tint = Color(hex: "C77D5A")

    /// Colour **and** dash together, in the same shape the chart and the swatch consume them.
    private func styleKeys(_ count: Int) -> [String] {
        (0..<count).map { index in
            let color = AccountSeriesStyle.color(index, tint: tint)
            let dash = AccountSeriesStyle.dash(index)
            return "\(String(describing: color))|\(dash)"
        }
    }

    func testEveryAccountLooksDifferentAtFourAccounts() {
        let keys = styleKeys(4)
        XCTAssertEqual(Set(keys).count, 4, "two of four series render identically: \(keys)")
    }

    func testEveryAccountLooksDifferentAtEightAccounts() {
        let keys = styleKeys(8)
        XCTAssertEqual(Set(keys).count, 8, "series collide at eight accounts: \(keys)")
    }

    /// The two accounts on the machine this was built for are the case that must never
    /// regress: different colour *and* different dash, so neither channel carries it alone.
    func testTheFirstTwoAccountsDifferInBothColourAndDash() {
        XCTAssertNotEqual(
            String(describing: AccountSeriesStyle.color(0, tint: tint)),
            String(describing: AccountSeriesStyle.color(1, tint: tint))
        )
        XCTAssertNotEqual(AccountSeriesStyle.dash(0), AccountSeriesStyle.dash(1))
    }
}

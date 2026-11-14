import AppKit
import SwiftUI
import XCTest

/// WP-C AC 8: burn text meets 4.5:1 on every surface it sits on, marks meet 3:1, and no burn
/// view reaches for the faint inks directly (they fail the text floor on the ground).
final class BurnContrastTests: XCTestCase {
    private static let burnDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("AIUsageDashboardApp/UI/Burn")

    /// WCAG 2 relative luminance of an sRGB colour.
    private func luminance(_ color: Color) -> Double {
        let ns = NSColor(color).usingColorSpace(.sRGB)!
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.040_45 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(ns.redComponent) + 0.7152 * channel(ns.greenComponent) + 0.0722 * channel(ns.blueComponent)
    }

    private func contrast(_ foreground: Color, on background: Color) -> Double {
        let (a, b) = (luminance(foreground), luminance(background))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Where burn text sits: the dashboard ground, the menu panel, the share sheet's panel, and
    /// the strip's hover fill.
    private let surfaces: [(String, Color)] = [
        ("ground", PadzyTheme.ground), ("menuPanel", PadzyTheme.menuPanel),
        ("panel", PadzyTheme.panel), ("hairline", PadzyTheme.hairline)
    ]

    func testBurnTextMeetsFourPointFiveToOne() {
        let text: [(String, Color)] = [
            ("ink", PadzyTheme.ink), ("ink2", PadzyTheme.ink2), ("caption", BurnTone.caption), ("warn", PadzyTheme.warn)
        ]
        for (name, ink) in text {
            for (surfaceName, surface) in surfaces {
                XCTAssertGreaterThanOrEqual(contrast(ink, on: surface), 4.5, "\(name) on \(surfaceName)")
            }
        }
    }

    func testMarksMeetThreeToOne() {
        for (surfaceName, surface) in surfaces {
            XCTAssertGreaterThanOrEqual(contrast(BurnTone.mark, on: surface), 3, "mark on \(surfaceName)")
            XCTAssertGreaterThanOrEqual(contrast(PadzyTheme.accent, on: surface), 3, "accent on \(surfaceName)")
        }
    }

    /// Why the faint inks are fenced off: measured, they fail the text floor.
    func testFaintInksFailTheTextFloor() {
        XCTAssertLessThan(contrast(PadzyTheme.ink4, on: PadzyTheme.ground), 4.5)
        XCTAssertLessThan(contrast(PadzyTheme.ink5, on: PadzyTheme.ground), 4.5)
    }

    func testBurnViewsUseTheToneNotTheFaintInks() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.burnDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "BurnTone.swift" }
        XCTAssertGreaterThan(files.count, 5, "the scan must see the burn sources at \(Self.burnDirectory.path)")
        var hits: [String] = []
        for file in files {
            for (index, line) in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n").enumerated()
            where line.contains("PadzyTheme.ink4") || line.contains("PadzyTheme.ink5") {
                hits.append("\(file.lastPathComponent):\(index + 1)")
            }
        }
        XCTAssertEqual(hits, [], "use BurnTone.caption for text, BurnTone.mark for icons and bars")
    }
}

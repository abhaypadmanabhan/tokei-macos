import SwiftUI
import AppKit

public struct PadzyTheme {
    public static let ground = Color(hex: "131316")
    public static let surface = Color(hex: "1D1D22")
    public static let ink = Color(hex: "ECECF1")
    public static let muted = Color(hex: "6E6E78")
    public static let accent = Color(hex: "FF3B70")
}

/// Corner-radius scale for the 2026-07-09 visual redesign (explicit user override
/// of the flat ≤4px aitracker default — see the Patch Bible §5 / design spec §2).
/// Cards are rounded surface panels over the flat ground; controls sit one step
/// tighter; `pill` is the fully-rounded capsule radius.
public enum PadzyRadius {
    public static let card: CGFloat = 12
    public static let control: CGFloat = 8
    public static let pill: CGFloat = 999
}

/// Categorical + sequential color for DATA ONLY (design spec §2). These hues may
/// appear inside charts, sparklines, and delta labels — never on buttons, nav,
/// active ticks, or any chrome/action affordance, which keep the single
/// `PadzyTheme.accent`. Review grep-guards against leaks (Bible §5).
public enum PadzyChartPalette {
    // Per-metric categorical hues (hero tiles' sparklines/deltas, stacked series).
    public static let input = Color(hex: "4C86FF")
    public static let output = Color(hex: "3DBE8B")
    public static let cacheRead = Color(hex: "A46BFF")
    public static let cacheWrite = Color(hex: "E8912D")

    // Signed-delta hues ("↑18% vs yesterday"). Direction is always ALSO carried
    // by a glyph/sign — color never signals alone.
    public static let deltaUp = Color(hex: "3DBE8B")
    public static let deltaDown = Color(hex: "FF4D4D")

    /// Sequential heatmap ramp, LOW → HIGH: surface → accent pink in 5 stops.
    public static let heatmapRamp: [Color] = [
        Color(hex: "1D1D22"),
        Color(hex: "562536"),
        Color(hex: "8E2C49"),
        Color(hex: "C7345D"),
        Color(hex: "FF3B70"),
    ]

    /// Donut slice ramp: `count` pink shades from accent `#FF3B70` down to
    /// `#7A1D35`, brightest first (largest slice takes the brightest shade).
    public static func donutRamp(_ count: Int) -> [Color] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [Color(hex: "FF3B70")] }
        let from: (Double, Double, Double) = (0xFF, 0x3B, 0x70)
        let to: (Double, Double, Double) = (0x7A, 0x1D, 0x35)
        return (0..<count).map { i in
            let t = Double(i) / Double(count - 1)
            return Color(
                .sRGB,
                red: (from.0 + (to.0 - from.0) * t) / 255,
                green: (from.1 + (to.1 - from.1) * t) / 255,
                blue: (from.2 + (to.2 - from.2) * t) / 255,
                opacity: 1
            )
        }
    }

    /// The ONE sanctioned gradient in the app: a pink→transparent vertical fill
    /// under line/area charts. Charts only — never on cards or chrome.
    public static var areaGradient: LinearGradient {
        LinearGradient(
            colors: [PadzyTheme.accent.opacity(0.32), PadzyTheme.accent.opacity(0.0)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension Color {
    public init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xff, int & 0xff)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xff, int >> 8 & 0xff, int & 0xff)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension Font {
    public static func mono(size: CGFloat) -> Font {
        if NSFont(name: "DM Mono", size: size) != nil {
            return .custom("DM Mono", size: size)
        } else {
            return .system(size: size, design: .monospaced)
        }
    }

    public static func display(size: CGFloat, weight: Font.Weight = .black) -> Font {
        if NSFont(name: "PP Neue Machina", size: size) != nil {
            return .custom("PP Neue Machina", size: size).weight(weight)
        } else {
            return .system(size: size, weight: weight, design: .default)
        }
    }
}

public struct TokenFormatter {
    public static func format(_ value: Int?) -> String {
        guard let val = value else { return "0" }
        let num = Double(val)
        if num >= 1_000_000_000 {
            return String(format: "%.1fB", num / 1_000_000_000)
        } else if num >= 1_000_000 {
            return String(format: "%.1fM", num / 1_000_000)
        } else if num >= 1_000 {
            return String(format: "%.1fK", num / 1_000)
        } else {
            return "\(val)"
        }
    }
}

/// Clean, unnumbered section header in the aitracker idiom: uppercase mono, tracked,
/// muted. Deliberately drops the old `NN / TITLE` numbered-kicker prefix (explicit
/// user override of the theme default) while keeping the mono + hairline discipline.
public struct SectionLabel: View {
    let title: String
    var size: CGFloat

    public init(_ title: String, size: CGFloat = 12) {
        self.title = title
        self.size = size
    }

    public var body: some View {
        Text(title.uppercased())
            .font(.mono(size: size))
            .tracking(size * 0.08)
            .foregroundColor(PadzyTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public struct HairlineDivider: View {
    @Environment(\.displayScale) private var displayScale

    public init() {}

    public var body: some View {
        Rectangle()
            .fill(PadzyTheme.muted.opacity(0.3))
            .frame(height: 1 / (displayScale > 0 ? displayScale : 2.0))
    }
}

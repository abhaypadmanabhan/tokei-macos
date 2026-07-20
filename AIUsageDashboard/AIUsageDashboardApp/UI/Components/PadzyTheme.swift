import SwiftUI
import AppKit

/// Core theme tokens for the aitracker (Tokei) surfaces.
///
/// WP-5 (2026-07-20) migrated the ramp app-wide to the "Tokei Dashboard" mockup
/// palette — a step darker and flatter than the prior shipped values: a near-black
/// ground with barely-lighter cells separated by crisp hairlines, and a 5-step ink
/// ramp doing the typographic hierarchy that size/weight alone did before.
///
/// The single product `accent` is reserved for active/selected/progress/primary
/// state. Per-agent identity colour is DATA, not chrome — see `AgentTint`.
public struct PadzyTheme {
    // Ground ramp (darkest → elevated).
    public static let ground = Color(hex: "0B0B0D")     // page behind the window
    public static let window = Color(hex: "0F0F12")     // window frame + content cells
    public static let surface = Color(hex: "0F0F12")    // cells/cards (was 1D1D22 pre-WP-5)
    public static let panel = Color(hex: "131316")      // elevated: drawers, popovers
    public static let statusBar = Color(hex: "0C0C0E")  // persistent bottom status bar
    public static let menuPanel = Color(hex: "141418")  // menu-bar popover panel
    public static let hairline = Color(hex: "1C1C21")   // 1px structural divider / cell border
    public static let border2 = Color(hex: "26262C")    // stronger border: inputs, drawer edge
    public static let scrim = Color(hex: "0B0B0D").opacity(0.6) // overlay behind drawers

    // Ink ramp — primary → faintest. `muted` is kept as an alias of `ink4` so the
    // large existing body of call sites keeps compiling unchanged.
    public static let ink = Color(hex: "ECECF1")        // ink1 · primary
    public static let ink2 = Color(hex: "C4C4CC")       // secondary text
    public static let ink3 = Color(hex: "9A9AA4")       // tertiary / captions
    public static let ink4 = Color(hex: "6E6E78")       // quaternary
    public static let ink5 = Color(hex: "54545C")       // faintest · kickers / axis labels
    public static let muted = Color(hex: "6E6E78")      // == ink4 (back-compat)

    public static let accent = Color(hex: "FF3B70")
    public static let accentHover = Color(hex: "FF5A86")

    // Semantic status hues (data/state signals — never chrome accent).
    public static let good = Color(hex: "6BBF8A")       // headroom / live / positive
    public static let warn = Color(hex: "D2A15C")       // ahead-of-pace / mid quota
    public static let danger = Color(hex: "FF4D4D")     // negative delta

    /// Quota fill colour by used %: `≥90` critical (accent) · `≥60` warn · else faint.
    public static func quotaColor(_ pct: Double) -> Color {
        if pct >= 90 { return accent }
        if pct >= 60 { return warn }
        return ink4
    }
}

/// Burn-vs-linear verdict for a quota window: is usage running ahead of, on, or
/// behind a steady linear burn for the elapsed fraction of the window?
public enum PaceVerdict {
    case ahead, onPace, headroom

    /// `pct` = used %, `elapsed` = fraction of the window elapsed (0…1).
    public init(pct: Double, elapsed: Double) {
        let linear = elapsed * 100
        if pct > linear * 1.12 { self = .ahead }
        else if pct < linear * 0.75 { self = .headroom }
        else { self = .onPace }
    }

    public var word: String {
        switch self {
        case .ahead: return "ahead"
        case .onPace: return "on pace"
        case .headroom: return "headroom"
        }
    }

    public var color: Color {
        switch self {
        case .ahead: return PadzyTheme.warn
        case .onPace: return Color(hex: "8E8E99")
        case .headroom: return PadzyTheme.good
        }
    }
}

/// Corner-radius scale. WP-5 adds `window` (10) and `cell`/`chip` (4) matching the
/// mockup; `card` (12) is the legacy `SectionCard` radius, retired as surfaces
/// migrate off the card-stack look.
public enum PadzyRadius {
    public static let window: CGFloat = 10
    public static let card: CGFloat = 12
    public static let cell: CGFloat = 4
    public static let chip: CGFloat = 4
    public static let control: CGFloat = 8
    public static let pill: CGFloat = 999
}

/// 4pt-based spacing scale (WP-5). Adopt in rebuilt surfaces so call-site literals
/// stop drifting (the prior UI hardcoded 18/20/24/28 inconsistently per view).
public enum PadzySpace {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let xxl: CGFloat = 28
    public static let xxxl: CGFloat = 40
}

/// Motion tokens. The mockup settles metric/tab/drill changes over ~650ms ease-out.
/// Every animated surface MUST fall back to a static path under Reduce Motion — gate
/// with `@Environment(\.accessibilityReduceMotion)` and pass `nil` when it is set.
public enum PadzyMotion {
    public static let settle: Animation = .easeOut(duration: 0.65)
    public static let quick: Animation = .easeOut(duration: 0.2)
    public static let toggle: Animation = .easeOut(duration: 0.15)
}

/// Categorical + sequential color for DATA ONLY (design spec §2). Per-METRIC hues
/// (input/output/cache) for stacked token-type splits; never on buttons, nav, or
/// active ticks. (Per-AGENT identity colour lives in `AgentTint`.)
public enum PadzyChartPalette {
    public static let input = Color(hex: "4C86FF")
    public static let output = Color(hex: "3DBE8B")
    public static let cacheRead = Color(hex: "A46BFF")
    public static let cacheWrite = Color(hex: "E8912D")

    public static let deltaUp = Color(hex: "3DBE8B")
    public static let deltaDown = Color(hex: "FF4D4D")

    /// Sequential heatmap ramp, LOW → HIGH. WP-5: a single neutral hue (mockup uses
    /// `rgba(202,202,214,α)`); the prior pink-accent ramp overloaded the accent.
    public static let heatmapRamp: [Color] = [
        Color(hex: "17171B"),
        Color(hex: "3A3A42"),
        Color(hex: "5E5E68"),
        Color(hex: "8E8E99"),
        Color(hex: "C4C4CC"),
    ]

    /// Neutral heatmap cell colour for a 0…1 intensity (mockup formula:
    /// `rgba(196,196,204, 0.05 + intensity*0.85)`).
    public static func heatCell(_ intensity: Double) -> Color {
        Color(.sRGB, red: 196.0 / 255, green: 196.0 / 255, blue: 204.0 / 255,
              opacity: 0.05 + max(0, min(1, intensity)) * 0.85)
    }

    /// Donut slice ramp: `count` pink shades from accent `#FF3B70` → `#7A1D35`.
    /// (Legacy — the WP-5 donut colours slices by `AgentTint` instead.)
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

    /// The one sanctioned gradient: a neutral ink→transparent fill under line/area
    /// charts (WP-5 recoloured from pink to neutral; per-agent history tints its own).
    public static var areaGradient: LinearGradient {
        LinearGradient(
            colors: [PadzyTheme.ink2.opacity(0.10), PadzyTheme.ink2.opacity(0.0)],
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
    /// Mono face for ALL numbers/timestamps/IDs/paths/metrics (Padzy Invariant 1).
    public static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if NSFont(name: "DM Mono", size: size) != nil {
            return .custom("DM Mono", size: size).weight(weight)
        } else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
    }

    /// Sans face for names, body copy, and controls. The mockup uses the system
    /// SF Pro stack here (not the display face) — numbers still use `.mono`.
    public static func sans(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
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
    /// Compact token count matching the mockup's `fmtTok`: `2.31B` · `533M` (≥100M
    /// drops decimals) · `8.90M` · `620K` · raw. `nil` = unknown → `—` (never `0`).
    public static func format(_ value: Int?) -> String {
        guard let val = value else { return "—" }
        let num = Double(val)
        if num >= 1_000_000_000 {
            return String(format: "%.2fB", num / 1_000_000_000)
        } else if num >= 1_000_000 {
            let m = num / 1_000_000
            return (m >= 100 ? String(format: "%.0fM", m) : String(format: "%.2fM", m))
        } else if num >= 1_000 {
            return "\(Int((num / 1_000).rounded()))K"
        } else {
            return "\(val)"
        }
    }
}

/// Clean, unnumbered section header in the aitracker idiom: uppercase mono, tracked,
/// faintest ink. Deliberately drops the `NN / TITLE` numbered kicker (user override).
public struct SectionLabel: View {
    let title: String
    var size: CGFloat

    public init(_ title: String, size: CGFloat = 10) {
        self.title = title
        self.size = size
    }

    public var body: some View {
        Text(title.uppercased())
            .font(.mono(size: size))
            .tracking(size * 0.16)
            .foregroundColor(PadzyTheme.ink5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public struct HairlineDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(PadzyTheme.hairline)
            .frame(height: 1)
    }
}

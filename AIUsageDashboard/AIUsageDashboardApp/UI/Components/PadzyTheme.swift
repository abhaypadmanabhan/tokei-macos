import SwiftUI
import AppKit

public struct PadzyTheme {
    public static let ground = Color(hex: "131316")
    public static let surface = Color(hex: "1D1D22")
    public static let ink = Color(hex: "ECECF1")
    public static let muted = Color(hex: "6E6E78")
    public static let accent = Color(hex: "FF3B70")
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

public struct EditorialKicker: View {
    let number: String
    let title: String

    public init(number: String, title: String) {
        self.number = number
        self.title = title
    }

    public var body: some View {
        Text("\(number) / \(title.uppercased())")
            .font(.mono(size: 12))
            .tracking(12 * 0.04)
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

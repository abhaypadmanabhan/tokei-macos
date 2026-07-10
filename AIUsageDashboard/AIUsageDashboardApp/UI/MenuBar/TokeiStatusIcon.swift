import SwiftUI
import AppKit

/// Burn ladder for the dynamic menu-bar mark, mapped from the tightest quota
/// window's used % (`MaxxerMath.tightestWindow`). Bands mirror the in-app
/// threshold emphasis (70 = accent onset, 90 = critical).
enum TokeiBurnLevel: Equatable {
    case idle          // no live quota anywhere, or nothing burned yet
    case low           // < 40%
    case medium        // 40–69%
    case high          // 70–89%
    case nearLimit     // 90–99% — "on fire"
    case limitReached  // ≥ 100%

    init(percent: Double?) {
        guard let percent, percent > 0 else { self = .idle; return }
        switch percent {
        case ..<40: self = .low
        case ..<70: self = .medium
        case ..<90: self = .high
        case ..<100: self = .nearLimit
        default: self = .limitReached
        }
    }

    /// Accent (colored) rendering starts where the app's threshold emphasis does.
    var usesAccent: Bool {
        switch self {
        case .idle, .low, .medium: return false
        case .high, .nearLimit, .limitReached: return true
        }
    }

    /// The subtle flame appears only when token-maxxing against a wall.
    var isOnFire: Bool { self == .nearLimit || self == .limitReached }
}

/// Dynamically-drawn menu-bar status icon built from the Tokei logo's four
/// slanted meter bars. The bars FILL left→right with the constraining window's
/// burn; tint walks ink → `PadzyTheme.accent` as the limit approaches, with a
/// small flame accent when near/at the limit. Monochrome states render as
/// template images (adapt to light/dark bars); accent states are colored.
/// Images are cached per state — same canvas for every state so the status
/// item never shifts width as burn changes.
enum TokeiStatusIcon {
    /// Full canvas: bars sit flush-bottom in a 15×11 box (the classic
    /// `TokeiMark.menuBarImage` geometry); the head-room row hosts the flame.
    private static let canvasSize = NSSize(width: 17, height: 14)
    private static let barsRect = CGRect(x: 0, y: 3, width: 15, height: 11)
    /// A small lick rising just past the tallest bar's tip — subtle, not a spike.
    private static let flameRect = CGRect(x: 12.9, y: 0.6, width: 3.4, height: 4.0)

    private static let accentColor = NSColor(srgbRed: 0xFF / 255, green: 0x3B / 255, blue: 0x70 / 255, alpha: 1)
    private static let dimAlpha: CGFloat = 0.3

    private static var cache: [String: NSImage] = [:]

    /// How many of the 4 bars read as filled for a burn %. Progressive quarters;
    /// any non-zero burn lights at least the first bar.
    static func filledBars(for percent: Double?) -> Int {
        guard let percent, percent > 0 else { return 0 }
        return min(4, max(1, Int(ceil(percent / 25))))
    }

    /// The status-icon image for the current burn. `percent` is the tightest
    /// window's used % (nil = no live quota → idle).
    static func image(percent: Double?) -> NSImage {
        let level = TokeiBurnLevel(percent: percent)
        let filled = filledBars(for: percent)
        let key = "\(level)-\(filled)"
        if let cached = cache[key] { return cached }

        let usesAccent = level.usesAccent
        let flame = level.isOnFire
        let image = NSImage(size: canvasSize, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // Paths are built in SwiftUI's top-left space; flip into AppKit's bottom-left.
            ctx.translateBy(x: 0, y: rect.height)
            ctx.scaleBy(x: 1, y: -1)

            let barColor: NSColor = usesAccent ? accentColor : .black
            for (index, path) in TokeiMark.barPaths(in: barsRect).enumerated() {
                let isFilled = index < filled
                ctx.addPath(path.cgPath)
                ctx.setFillColor(barColor.withAlphaComponent(isFilled ? 1 : dimAlpha).cgColor)
                ctx.fillPath()
            }

            if flame {
                ctx.addPath(flamePath(in: flameRect).cgPath)
                ctx.setFillColor(accentColor.cgColor)
                ctx.fillPath()
            }
            return true
        }
        // Template only where monochrome is right; accent states keep their color.
        image.isTemplate = !usesAccent
        cache[key] = image
        return image
    }

    /// Small teardrop flame — deliberately understated at menu-bar size.
    private static func flamePath(in rect: CGRect) -> Path {
        var path = Path()
        let base = CGPoint(x: rect.midX, y: rect.maxY)
        let tip = CGPoint(x: rect.midX + rect.width * 0.16, y: rect.minY)
        path.move(to: base)
        path.addQuadCurve(to: tip, control: CGPoint(x: rect.maxX, y: rect.midY))
        path.addQuadCurve(to: base, control: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.12))
        path.closeSubpath()
        return path
    }

    // MARK: Sync spinner

    /// Number of discrete spinner frames; `MenuBarLabel` advances the phase on a
    /// timer while a sync is in flight (static frame under Reduce Motion).
    static let spinnerPhases = 8

    /// A small circular sync spinner: faint full ring + a 270° accent arc whose
    /// start angle rotates with `phase`. Colored image (the accent IS the state).
    static func spinnerImage(phase: Int) -> NSImage {
        let normalized = ((phase % spinnerPhases) + spinnerPhases) % spinnerPhases
        let key = "spinner-\(normalized)"
        if let cached = cache[key] { return cached }

        let size = NSSize(width: 11, height: 11)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let lineWidth: CGFloat = 1.6
            let radius = min(rect.width, rect.height) / 2 - lineWidth / 2
            let center = CGPoint(x: rect.midX, y: rect.midY)

            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)

            ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
            ctx.setStrokeColor(accentColor.withAlphaComponent(0.25).cgColor)
            ctx.strokePath()

            let start = -CGFloat(normalized) / CGFloat(spinnerPhases) * 2 * .pi
            ctx.addArc(center: center, radius: radius, startAngle: start,
                       endAngle: start - 1.5 * .pi, clockwise: true)
            ctx.setStrokeColor(accentColor.cgColor)
            ctx.strokePath()
            return true
        }
        image.isTemplate = false
        cache[key] = image
        return image
    }
}

// MARK: - Previews

#Preview("Burn ladder + spinner") {
    let states: [(String, Double?)] = [
        ("IDLE", nil), ("LOW 18%", 18), ("MEDIUM 52%", 52),
        ("HIGH 74%", 74), ("NEAR LIMIT 93%", 93), ("LIMIT 100%", 104),
    ]
    return VStack(alignment: .leading, spacing: 14) {
        ForEach(states, id: \.0) { name, pct in
            HStack(spacing: 12) {
                Image(nsImage: TokeiStatusIcon.image(percent: pct))
                Text(name).font(.mono(size: 11)).foregroundColor(PadzyTheme.muted)
            }
        }
        HStack(spacing: 12) {
            ForEach(0..<TokeiStatusIcon.spinnerPhases, id: \.self) { phase in
                Image(nsImage: TokeiStatusIcon.spinnerImage(phase: phase))
            }
            Text("SYNCING").font(.mono(size: 11)).foregroundColor(PadzyTheme.muted)
        }
    }
    .padding(24)
    .background(PadzyTheme.surface)
}

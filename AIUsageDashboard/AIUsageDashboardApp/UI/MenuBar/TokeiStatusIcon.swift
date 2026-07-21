import SwiftUI
import AppKit

/// Dynamically-drawn menu-bar status icon: the Tokei swoosh-square that FILLS
/// black → accent as the constraining quota window's burn rises, matching the
/// brand's usage-states row (0% all-ink · 50% top-half accent · 80% · 100% all
/// accent). The white swoosh is punched as a transparent cut so the mark reads
/// on any menu-bar background.
///
/// Rendering: the idle frame (no burn) is a template image, so an all-ink square
/// adapts to the bar (dark on light menus, light on dark). Once any accent is
/// present the image is colored — the accent IS the state. Images are cached per
/// fill step on a fixed square canvas, so the status item never shifts width as
/// burn changes.
///
/// Deliberately NOT a `TimelineView`: this feeds a `MenuBarExtra` label that
/// SwiftUI snapshots into the status item; a self-driving clock breaks that
/// render (see `MenuBarLabel`). Every state is a plain cached `NSImage`.
enum TokeiStatusIcon {
    /// Square menu-bar canvas; the mark insets a hair for breathing room.
    private static let canvasSize = NSSize(width: 18, height: 18)
    private static let markRect = CGRect(x: 1, y: 1, width: 16, height: 16)

    // Brand ink (#131316) and the single product accent (#FF3B70), sRGB-resolved
    // for bitmap drawing with a defensive fallback if conversion ever returns nil.
    private static let inkColor = NSColor(srgbRed: 0x13 / 255, green: 0x13 / 255, blue: 0x16 / 255, alpha: 1)
    private static let accentColor = NSColor(PadzyTheme.accent).usingColorSpace(.sRGB)
        ?? NSColor(srgbRed: 0xFF / 255, green: 0x3B / 255, blue: 0x70 / 255, alpha: 1)

    private static var cache: [String: NSImage] = [:]

    /// How many of 4 quarters read as filled for a burn % — retained as the
    /// `MenuBarLabel` contract API (the mark now fills continuously; this stays a
    /// stable coarse indicator for any caller).
    static func filledBars(for percent: Double?) -> Int {
        guard let percent, percent > 0 else { return 0 }
        return min(4, max(1, Int(ceil(percent / 25))))
    }

    /// Accent fill fraction (0…1) for a burn %. `nil`/≤0 → idle (all ink).
    private static func fillFraction(for percent: Double?) -> CGFloat {
        guard let percent, percent > 0 else { return 0 }
        return CGFloat(min(100, percent) / 100)
    }

    /// The status-icon image for the current burn. `percent` is the tightest
    /// window's used % (nil = no live quota → idle).
    static func image(percent: Double?) -> NSImage {
        let fill = fillFraction(for: percent)
        let idle = fill <= 0
        // Quantize to whole-percent steps so the cache is bounded but the fill
        // still reads as continuous.
        let key = "mark-\(Int((fill * 100).rounded()))"
        if let cached = cache[key] { return cached }

        let image = NSImage(size: canvasSize, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // Paths are built in SwiftUI's top-left space; flip into AppKit's.
            ctx.translateBy(x: 0, y: rect.height)
            ctx.scaleBy(x: 1, y: -1)

            let square = TokeiMark.roundedSquarePath(in: markRect).cgPath

            // Fill the square: ink base, then the accent occupying the TOP `fill`
            // fraction of the height (top-left space → minY is the top edge).
            ctx.saveGState()
            ctx.addPath(square)
            ctx.clip()
            if idle {
                ctx.setFillColor(NSColor.black.cgColor) // template → adapts to the bar
                ctx.fill(markRect)
            } else {
                ctx.setFillColor(inkColor.cgColor)
                ctx.fill(markRect)
                let accentHeight = markRect.height * fill
                let accentRect = CGRect(x: markRect.minX, y: markRect.minY,
                                        width: markRect.width, height: accentHeight)
                ctx.setFillColor(accentColor.cgColor)
                ctx.fill(accentRect)
            }
            ctx.restoreGState()

            // Punch the swoosh transparent (clipped to the square) so it reads on
            // any background.
            ctx.saveGState()
            ctx.addPath(square)
            ctx.clip()
            ctx.setBlendMode(.clear)
            ctx.addPath(TokeiMark.swooshPath(in: markRect).cgPath)
            ctx.fillPath()
            ctx.restoreGState()
            return true
        }
        // Adapt only while all-ink; colored once the accent IS the state.
        image.isTemplate = idle
        cache[key] = image
        return image
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

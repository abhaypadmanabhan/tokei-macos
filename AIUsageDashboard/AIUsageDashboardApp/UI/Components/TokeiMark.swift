import SwiftUI
import AppKit

/// The Tokei brand mark: four slanted meter bars ascending left to right.
/// Monochrome Shape — fill with `.primary` in-app; use `menuBarImage` for the
/// MenuBarExtra label (template NSImage renders reliably where Shapes don't).
struct TokeiMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let barCount = 4
        let gapRatio: CGFloat = 0.55
        let unit = rect.width / (CGFloat(barCount) + gapRatio * CGFloat(barCount - 1))
        let gap = unit * gapRatio
        let slant = unit * 0.5

        for i in 0..<barCount {
            let x = CGFloat(i) * (unit + gap)
            let heightFraction = 0.35 + 0.65 * CGFloat(i) / CGFloat(barCount - 1)
            let barHeight = rect.height * heightFraction
            let bottom = rect.maxY
            let top = rect.maxY - barHeight
            path.move(to: CGPoint(x: x, y: bottom))
            path.addLine(to: CGPoint(x: x + slant * (barHeight / rect.height), y: top))
            path.addLine(to: CGPoint(x: x + unit + slant * (barHeight / rect.height), y: top))
            path.addLine(to: CGPoint(x: x + unit, y: bottom))
            path.closeSubpath()
        }
        return path
    }

    /// Template image of the mark for the system menu bar (adapts to bar appearance).
    static let menuBarImage: NSImage = {
        let size = NSSize(width: 15, height: 11)
        let image = NSImage(size: size, flipped: false) { rect in
            let cgPath = TokeiMark().path(in: CGRect(origin: .zero, size: rect.size)).cgPath
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // Path is built in SwiftUI's top-left space; flip into AppKit's bottom-left.
            ctx.translateBy(x: 0, y: rect.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.addPath(cgPath)
            ctx.setFillColor(.black)
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

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

/// Sparkline for daily token totals. Flat hairline when fewer than 2 points.
struct Sparkline: View {
    let values: [Int]

    var body: some View {
        GeometryReader { geo in
            if values.count >= 2, let maxValue = values.max(), maxValue > 0 {
                Path { path in
                    let stepX = geo.size.width / CGFloat(values.count - 1)
                    for (i, v) in values.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = geo.size.height * (1 - CGFloat(v) / CGFloat(maxValue) * 0.9)
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                // Data trend, not a state — rendered in ink so the accent stays reserved.
                .stroke(PadzyTheme.ink.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            } else {
                Rectangle()
                    .fill(PadzyTheme.muted.opacity(0.4))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

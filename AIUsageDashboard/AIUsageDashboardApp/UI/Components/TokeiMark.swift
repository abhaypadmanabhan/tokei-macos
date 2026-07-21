import SwiftUI
import AppKit

/// The Tokei brand mark: a rounded-square split accent-over-ink with a white
/// swoosh sweeping from the right edge down to the lower-left.
///
/// The static in-app logo renders the `BrandMark` asset (the exact brand art,
/// crisp at any size and identical to the app icon). The shared vector geometry
/// below is the single source of truth for the swoosh + square silhouette and is
/// reused by the dynamic menu-bar `TokeiStatusIcon`, which must draw the mark
/// itself so it can fill with burn.
struct TokeiMark: View {
    var size: CGFloat = 28

    var body: some View {
        Image("BrandMark")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityLabel("Tokei")
    }

    // MARK: - Shared geometry (used by TokeiStatusIcon)

    /// Corner radius as a fraction of the square's side (Apple Big Sur grid,
    /// matching the app-icon master).
    static let cornerFraction: CGFloat = 0.225

    /// Swoosh stroke width as a fraction of the square's side.
    static let swooshWidthFraction: CGFloat = 0.15

    /// The rounded-square silhouette filling `rect`.
    static func roundedSquarePath(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * cornerFraction)
    }

    /// The swoosh as a fillable region: a single bold curve stroked round, cubic
    /// fitted to the master's centerline (enters at the right edge ~⅓ down,
    /// exits at the lower-left). Callers clip it to `roundedSquarePath` so the
    /// caps meet the square's edges cleanly.
    static func swooshPath(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + nx * w, y: rect.minY + ny * h)
        }
        var centerline = Path()
        centerline.move(to: p(0.99, 0.33))
        centerline.addCurve(to: p(0.26, 0.99), control1: p(0.66, 0.35), control2: p(0.40, 0.60))
        return centerline.strokedPath(
            StrokeStyle(lineWidth: min(w, h) * swooshWidthFraction, lineCap: .round, lineJoin: .round)
        )
    }
}

// MARK: - Previews

#Preview("TokeiMark") {
    HStack(spacing: 20) {
        ForEach([16, 24, 40, 64] as [CGFloat], id: \.self) { s in
            TokeiMark(size: s)
        }
    }
    .padding(24)
    .background(PadzyTheme.surface)
}

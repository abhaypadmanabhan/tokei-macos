import SwiftUI

/// Trimmed-ring utilization gauge ("72% of session limit", design spec §3).
/// Accent fill over a muted track, mono % in the center, caps micro label
/// underneath. Plain value input (percent 0…100); a used/limit convenience init
/// mirrors the `Utilization` shape without coupling to it.
struct CircularGauge: View {
    /// 0…100; clamped for drawing so a reading past the ceiling can't overshoot.
    let percent: Double
    var label: String? = nil
    var size: CGFloat = 108

    init(percent: Double, label: String? = nil, size: CGFloat = 108) {
        self.percent = percent
        self.label = label
        self.size = size
    }

    init(used: Double, limit: Double, label: String? = nil, size: CGFloat = 108) {
        self.init(
            percent: limit > 0 ? used / limit * 100 : 0,
            label: label,
            size: size
        )
    }

    private var clamped: Double { min(100, max(0, percent)) }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(PadzyTheme.muted.opacity(0.18), lineWidth: size * 0.075)
                Circle()
                    .trim(from: 0, to: CGFloat(clamped / 100))
                    .stroke(
                        PadzyTheme.accent,
                        style: StrokeStyle(lineWidth: size * 0.075, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(Int(round(percent)))%")
                    .font(.mono(size: size * 0.24))
                    .monospacedDigit()
                    .foregroundColor(PadzyTheme.ink)
            }
            .frame(width: size, height: size)

            if let label {
                Text(label.uppercased())
                    .font(.mono(size: 10))
                    .tracking(10 * 0.08)
                    .foregroundColor(PadzyTheme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(round(percent))) percent\(label.map { " of \($0)" } ?? "")")
    }
}

#Preview("Gauge states") {
    HStack(spacing: 32) {
        CircularGauge(percent: 72, label: "of session limit")
        CircularGauge(percent: 8, label: "weekly")
        CircularGauge(percent: 100, label: "maxed")
        CircularGauge(used: 47, limit: 100, label: "used / limit", size: 84)
    }
    .padding(32)
    .background(PadzyTheme.ground)
}

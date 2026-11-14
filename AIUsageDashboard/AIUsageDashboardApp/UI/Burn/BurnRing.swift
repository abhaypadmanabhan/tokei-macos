import SwiftUI
import AIUsageDashboardCore

/// Today's progress to the daily goal as a ring, in the one accent.
///
/// The care detail: past 1× the ring does not stop full. The first lap dims and the next lap
/// runs over it, cut from it by a thin line of the surface colour, so "beyond the goal" reads
/// at a glance without a second hue or a shadow (theme invariants 3 and 5). The fill rolls
/// with the live-number timing and snaps under Reduce Motion.
struct BurnRing<Center: View>: View {
    /// Burned ÷ goal; `nil` without a goal (track only).
    let progress: Double?
    let diameter: CGFloat
    let lineWidth: CGFloat
    /// The colour behind the ring, used for the cut between laps.
    var surface: Color = PadzyTheme.ground
    @ViewBuilder var center: () -> Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let laps = BurnRingLaps(progress: progress)
        ZStack {
            Circle()
                .stroke(PadzyTheme.border2, lineWidth: lineWidth)
            if laps.current > 0 || laps.completed > 0 {
                arc(laps.completed > 0 ? 1 : laps.current)
                    .stroke(PadzyTheme.accent.opacity(laps.completed > 0 ? 0.4 : 1), style: stroke(lineWidth))
            }
            if laps.completed > 0 && laps.current > 0 {
                arc(laps.current)
                    .stroke(surface, style: stroke(lineWidth + 3))
                arc(laps.current)
                    .stroke(PadzyTheme.accent, style: stroke(lineWidth))
            }
            center()
        }
        .frame(width: diameter, height: diameter)
        .animation(LiveNumberMotion.animation(reduceMotion: reduceMotion), value: progress)
    }

    private func arc(_ fraction: Double) -> some Shape {
        Circle()
            .trim(from: 0, to: fraction)
            .rotation(.degrees(-90))
    }

    private func stroke(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round)
    }
}

// MARK: - Celebration

/// Sparks that fly out from a ring or badge on a spring and fade. One value drives every spark,
/// so SwiftUI interpolates a single number per frame and the canvas redraws; nothing ticks once
/// the spring settles.
struct EmberBurst: View, Animatable {
    var progress: Double
    let sparks: Int
    /// How far past the edge the sparks travel, in points.
    let reach: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let start = min(size.width, size.height) / 2 - reach
            let fade = max(0, min(1, 1 - progress))
            for index in 0..<sparks {
                let angle = Double(index) * 2.399_963 // golden angle: even, never a grid
                let speed = 0.55 + 0.45 * Self.noise(index)
                let travel = start + reach * CGFloat(speed * progress)
                let point = CGPoint(x: center.x + CGFloat(cos(angle)) * travel,
                                    y: center.y + CGFloat(sin(angle)) * travel)
                let radius = CGFloat(1.4 + 1.8 * speed) * CGFloat(1 - 0.45 * min(1, progress))
                let color = index % 3 == 0 ? PadzyTheme.ink : PadzyTheme.accent
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(color.opacity(fade))
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Deterministic 0…1 per spark, so a replay looks the same.
    private static func noise(_ index: Int) -> Double {
        let value = sin(Double(index) * 12.9898) * 43_758.5453
        return value - value.rounded(.down)
    }
}

/// Plays `celebration` once on the view it decorates: a spring-driven ember burst and a glow
/// (Goblin mode gets more sparks, a longer reach and a second wave), or under Reduce Motion a
/// static accent outline for a few seconds. Drawn as overlays with hit testing off, so it never
/// moves a control under the pointer or takes focus; the `.task` ends with it, so no timer
/// outlives the view.
struct CelebrationModifier: ViewModifier {
    let celebration: BurnCelebration?
    /// Size of the burst area relative to the decorated view.
    var spread: CGFloat = 2.2
    var shape: CelebrationShape = .circle
    let onFinish: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playing: BurnCelebration?
    @State private var wave1 = 0.0
    @State private var wave2 = 0.0
    @State private var glow = 0.0

    enum CelebrationShape {
        case circle
        case cell
    }

    /// Reduce Motion, or its debug stand-in for captures (`-TokeiReduceMotion YES`).
    private var staticOnly: Bool {
        #if DEBUG
        if BurnDebug.forceReduceMotion { return true }
        #endif
        return reduceMotion
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if let playing {
                    if staticOnly {
                        outline.stroke(PadzyTheme.accent, lineWidth: 2)
                    } else {
                        ZStack {
                            outline
                                .stroke(PadzyTheme.accent, lineWidth: 3)
                                .blur(radius: 10 * glow)
                                .opacity(glow)
                            GeometryReader { proxy in
                                let side = max(proxy.size.width, proxy.size.height) * spread
                                ZStack {
                                    EmberBurst(progress: wave1, sparks: playing.isGoblinMode ? 34 : 16,
                                               reach: side * (playing.isGoblinMode ? 0.42 : 0.3))
                                    if playing.isGoblinMode {
                                        EmberBurst(progress: wave2, sparks: 22, reach: side * 0.3)
                                            .rotationEffect(.degrees(17))
                                    }
                                }
                                .frame(width: side, height: side)
                                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
            .task(id: celebration?.id) { await play() }
    }

    private var outline: some Shape {
        switch shape {
        case .circle: return AnyShape(Circle())
        case .cell: return AnyShape(RoundedRectangle(cornerRadius: PadzyRadius.cell, style: .continuous))
        }
    }

    private func play() async {
        guard let celebration else { return }
        guard !celebration.isStale(at: Date()) else {
            onFinish(celebration.id)
            return
        }
        playing = celebration
        defer {
            playing = nil
            onFinish(celebration.id)
        }
        if staticOnly {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            return
        }
        let big = celebration.isGoblinMode
        wave1 = 0
        wave2 = 0
        glow = 0
        withAnimation(.spring(response: big ? 1.3 : 0.9, dampingFraction: 0.9)) { wave1 = 1 }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { glow = 1 }
        try? await Task.sleep(nanoseconds: 350_000_000)
        if big { withAnimation(.spring(response: 1.4, dampingFraction: 0.9)) { wave2 = 1 } }
        withAnimation(.easeOut(duration: big ? 1.2 : 0.7)) { glow = 0 }
        try? await Task.sleep(nanoseconds: big ? 1_700_000_000 : 900_000_000)
    }
}

extension View {
    /// One-shot celebration for a burn moment; see `CelebrationModifier`.
    func celebration(
        _ celebration: BurnCelebration?,
        spread: CGFloat = 2.2,
        shape: CelebrationModifier.CelebrationShape = .circle,
        onFinish: @escaping (UUID) -> Void
    ) -> some View {
        modifier(CelebrationModifier(celebration: celebration, spread: spread, shape: shape, onFinish: onFinish))
    }
}

// MARK: - Previews

#Preview("Ring · under, at, over the goal") {
    HStack(spacing: 28) {
        ForEach([nil, 0.0, 0.62, 1.0, 1.51, 2.4] as [Double?], id: \.self) { value in
            BurnRing(progress: value, diameter: 96, lineWidth: 10) {
                Text(BurnCopy.progressText(value))
                    .font(.mono(size: 17, weight: .semibold))
                    .foregroundColor(PadzyTheme.ink)
            }
        }
    }
    .padding(32)
    .background(PadzyTheme.ground)
}

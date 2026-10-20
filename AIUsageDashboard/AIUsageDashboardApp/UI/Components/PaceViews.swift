import SwiftUI
import AIUsageDashboardCore

/// Words for a `QuotaPace`, in the maxxer voice: behind the clock is room you can still
/// spend before the reset, ahead is burning faster than the window refills. Shared by the
/// Overview bars, the drill-in rows and the menu-bar popover so they never word it twice.
enum PaceCopy {
    /// Whole points between used and elapsed share, never negative.
    static func points(_ pace: QuotaPace) -> Int { Int(abs(pace.delta).rounded()) }

    /// Sentence-length form for rows with room.
    static func phrase(_ pace: QuotaPace) -> String {
        switch pace.state {
        case .behind: return "\(points(pace)) pts under pace, room to use before reset"
        case .onPace: return "On pace with the clock"
        case .ahead: return "\(points(pace)) pts ahead of the clock"
        }
    }

    /// Short form for the dense popover.
    static func compact(_ pace: QuotaPace) -> String {
        switch pace.state {
        case .behind: return "\(points(pace)) pts of room"
        case .onPace: return "On pace"
        case .ahead: return "\(points(pace)) pts ahead"
        }
    }

    /// The state's mark. Form carries the state (direction of the arrow), so every state
    /// shares one ink and no colour has to explain it.
    static func symbol(_ state: QuotaPace.State) -> String {
        switch state {
        case .behind: return "arrow.down.right"
        case .onPace: return "equal"
        case .ahead: return "arrow.up.right"
        }
    }

    /// Spoken form; the elapsed share is the tick a sighted reader sees on the bar.
    static func accessibility(_ pace: QuotaPace) -> String {
        "\(phrase(pace)). \(Int(pace.elapsedPercent.rounded())) percent of the window has passed."
    }
}

/// Mark + words for a pace. Caller decides whether it shows; `nil` pace is never drawn.
struct PaceLine: View {
    let pace: QuotaPace
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: PaceCopy.symbol(pace.state))
                .font(.system(size: 12, weight: .semibold))
                .accessibilityHidden(true)
            Text(compact ? PaceCopy.compact(pace) : PaceCopy.phrase(pace))
                .font(.sans(size: 15))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundColor(PadzyTheme.ink3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PaceCopy.accessibility(pace))
    }
}

/// The state's mark alone, for rows that carry no words (the menu-bar quota rows). The
/// slot keeps its width when there is no pace, so bars line up row to row.
struct PaceMark: View {
    let pace: QuotaPace?

    var body: some View {
        Group {
            if let pace {
                Image(systemName: PaceCopy.symbol(pace.state))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PadzyTheme.ink3)
                    .help(PaceCopy.phrase(pace))
            } else {
                Color.clear
            }
        }
        .frame(width: 14)
        .accessibilityHidden(true)
    }
}

/// The elapsed-time tick on a quota gauge: where an even burn would sit right now. It
/// stands taller than the track so it reads as a mark on the bar, not part of the fill,
/// and stays ink in every state — the fill and the words carry the reading.
struct ElapsedTick: View {
    /// Share of the window that has passed, 0…100.
    let elapsedPercent: Double
    /// Width of the gauge the tick sits on.
    let width: CGFloat
    var height: CGFloat = 12

    var body: some View {
        let tickX = width * CGFloat(max(0, min(100, elapsedPercent)) / 100)
        Rectangle()
            .fill(PadzyTheme.ink2)
            .frame(width: 1.5, height: height)
            .offset(x: min(max(0, tickX - 0.75), max(0, width - 1.5)))
            .help("\(Int(elapsedPercent.rounded()))% of the window has passed")
            .accessibilityHidden(true)
    }
}

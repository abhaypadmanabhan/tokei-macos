import SwiftUI
import AIUsageDashboardCore

/// Mark + words for a pace, then the forecast when one is honest ("Lasts to reset",
/// "Runs out ~3:40 PM, 6 h before reset"). The words wrap rather than truncate: a pace
/// sentence cut to "room to…" says nothing. Caller decides whether it shows; `nil` pace is
/// never drawn. The words themselves live in `PaceCopy`.
struct PaceLine: View {
    let pace: QuotaPace
    /// Reset of the window the pace was read off; the forecast needs it for its lead time.
    var resetAt: Date?
    var compact = false
    /// The clock the pace was computed against, so the forecast agrees with it.
    var now = Date()

    private var forecast: String? { PaceCopy.forecast(pace, resetAt: resetAt, now: now) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: PaceCopy.symbol(pace.state))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(PadzyTheme.ink3)
                .accessibilityHidden(true)
            words
                .font(.sans(size: 15))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PaceCopy.accessibility(pace, forecast: forecast))
    }

    /// Pace in the muted ink. A forecast that says the window will not last is set in full
    /// ink and medium weight: the one reading on the row that needs a person, carried by
    /// its words and weight rather than a hue.
    private var words: Text {
        let pacePart = Text(compact ? PaceCopy.compact(pace) : PaceCopy.phrase(pace))
            .foregroundColor(PadzyTheme.ink3)
        guard let forecast else { return pacePart }
        let urgent = PaceCopy.isUrgent(pace.forecast)
        return pacePart
            + Text(" · ").foregroundColor(PadzyTheme.ink5)
            + Text(forecast)
                .foregroundColor(urgent ? PadzyTheme.ink : PadzyTheme.ink3)
                .fontWeight(urgent ? .medium : .regular)
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

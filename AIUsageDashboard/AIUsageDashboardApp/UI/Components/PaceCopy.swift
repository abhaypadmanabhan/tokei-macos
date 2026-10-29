import Foundation
import AIUsageDashboardCore

/// Words for a `QuotaPace`, in the maxxer voice: behind the clock is room you can still
/// spend before the reset, ahead is burning faster than the window refills. Shared by the
/// Overview bars, the drill-in rows and the menu-bar popover so they never word it twice.
///
/// Pure (Foundation only) so `AIUsageDashboardCoreTests` compiles it directly; the views
/// that draw these words live in `PaceViews.swift`.
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
    static func accessibility(_ pace: QuotaPace, forecast: String? = nil) -> String {
        let base = "\(phrase(pace)). \(Int(pace.elapsedPercent.rounded())) percent of the window has passed."
        guard let forecast else { return base }
        return "\(base) \(forecast)."
    }

    // MARK: - Forecast

    /// "Does this window last until it resets?", from `QuotaPace.forecast`:
    /// "Runs out ~3:40 PM, 6 h before reset" / "Lasts to reset" / "Out until 9:00 PM",
    /// and `nil` while it is too early to project. Times follow the locale's 12/24-hour
    /// choice; a time on another day carries its weekday.
    static func forecast(
        _ forecast: QuotaPace.Forecast,
        resetAt: Date?,
        now: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String? {
        switch forecast {
        case .tooEarly:
            return nil
        case .lastsToReset:
            return "Lasts to reset"
        case .runsOut(let runsOutAt):
            // A projection is not minute-exact; a 5-minute grid also keeps the label from
            // ticking on every refresh.
            let rounded = Date(timeIntervalSinceReferenceDate:
                (runsOutAt.timeIntervalSinceReferenceDate / 300).rounded() * 300)
            let time = clockTime(rounded, now: now, locale: locale, timeZone: timeZone)
            // The lead is measured from the time the label shows, so a reader can check it.
            guard let resetAt, resetAt > rounded else { return "Runs out ~\(time)" }
            return "Runs out ~\(time), \(lead(resetAt.timeIntervalSince(rounded))) before reset"
        case .exhausted:
            guard let resetAt else { return "Out until reset" }
            return "Out until \(clockTime(resetAt, now: now, locale: locale, timeZone: timeZone))"
        }
    }

    /// Forecast for a pace read off a window with this reset time.
    static func forecast(_ pace: QuotaPace, resetAt: Date?, now: Date) -> String? {
        forecast(pace.forecast, resetAt: resetAt, now: now)
    }

    /// Whether the forecast says the window does not last — the reading that needs a person.
    static func isUrgent(_ forecast: QuotaPace.Forecast) -> Bool {
        switch forecast {
        case .runsOut, .exhausted: return true
        case .tooEarly, .lastsToReset: return false
        }
    }

    /// "40 min" / "6 h" / "3 d": the gap between running out and the reset.
    static func lead(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(max(1, minutes)) min" }
        let hours = Int((seconds / 3_600).rounded())
        if hours < 48 { return "\(hours) h" }
        return "\(Int((seconds / 86_400).rounded())) d"
    }

    /// A time of day; on another calendar day it gains the weekday, and beyond a week the date.
    static func clockTime(_ date: Date, now: Date, locale: Locale, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        let template: String
        if calendar.isDate(date, inSameDayAs: now) {
            template = "jmm"
        } else if date.timeIntervalSince(now) < 6 * 86_400 {
            template = "EEEjmm"
        } else {
            template = "MMMdjmm"
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

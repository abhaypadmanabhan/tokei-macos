import Foundation

/// Words for numbers shown from the last run's saved snapshot, before the first live sync
/// lands: an honest age ("Saved 8 days ago · updating…") and the day the saved "today"
/// figures belong to. Pure (Foundation only) so the Core test bundle compiles it.
enum SavedAgeCopy {
    /// "just now", "4 min ago", "3 h ago", "1 day ago", "8 days ago".
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) h ago" }
        let days = hours / 24
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }

    /// The status-strip line while saved numbers are on screen.
    static func statusLine(savedAt: Date?, updating: Bool, now: Date) -> String {
        let saved = savedAt.map { "Saved \(ago($0, now: now))" } ?? "Saved earlier"
        return updating ? "\(saved) · updating…" : saved
    }

    /// Which day a saved "today" figure describes: "today", or "on Tue 20 Oct" when the
    /// snapshot was saved on an earlier day (its "today" is that day, not this one).
    static func dayPhrase(savedAt: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let savedAt, !calendar.isDate(savedAt, inSameDayAs: now) else { return "today" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return "on \(formatter.string(from: savedAt))"
    }
}

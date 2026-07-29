import Foundation

/// How every trend chart phrases a day: "how long ago" on the axis, a real date in the
/// callout.
///
/// Shared because the provider's history chart and the per-account chart sit on the same
/// drill-in, one above the other. Two copies of this wording drift the moment either is
/// edited, and two charts on one screen labelling the same day differently reads as a bug
/// in the data rather than in the formatter.
enum ChartDayLabel {
    /// X-axis label: `TODAY` for the current day, else the whole-day distance back
    /// (`7D`). Dates read as "how long ago", not as a calendar.
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        return days <= 0 ? "TODAY" : "\(days)D"
    }

    /// Callout header: the actual day (`Mon Jul 27`), because a hover is where the
    /// relative idiom stops being enough.
    static func callout(_ date: Date) -> String {
        calloutFormatter.string(from: date)
    }

    private static let calloutFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d"
        return formatter
    }()
}

import Foundation

public enum DateHelpers {
    public static func startOfToday(in calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: Date())
    }
}

import Foundation

public enum UsageRange: Sendable, Equatable {
    case today
    case sevenDay
    case thirtyDay
    case ninetyDay
    case week
    case month
    case lifetime
    case custom(start: Date, end: Date)
}

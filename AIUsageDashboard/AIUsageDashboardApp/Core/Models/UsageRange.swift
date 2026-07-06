import Foundation

public enum UsageRange: Sendable {
    case today
    case week
    case month
    case lifetime
    case custom(start: Date, end: Date)
}

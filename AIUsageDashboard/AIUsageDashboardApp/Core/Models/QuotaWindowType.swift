import Foundation

public enum QuotaWindowType: String, CaseIterable, Sendable {
    case session
    case daily
    case weekly
    case fiveHour
    case monthly
    case credits
    case perModel
    case lifetime
}

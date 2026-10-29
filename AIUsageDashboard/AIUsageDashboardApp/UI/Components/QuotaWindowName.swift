import Foundation
import AIUsageDashboardCore

/// One way to name a quota window and whose it is, shared by the drill-in rows, the
/// Overview quota hero and the menu-bar popover so a window is never called two things.
enum QuotaWindowName {
    /// "Session", "Weekly", "5-hour"…: the window type alone.
    static func typeName(_ type: QuotaWindowType) -> String {
        switch type {
        case .session: return "Session"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .fiveHour: return "5-hour"
        case .monthly: return "Monthly"
        case .credits: return "Credits"
        case .perModel: return "Per model"
        case .lifetime: return "Lifetime"
        }
    }

    /// Row label: the provider's own label when it gives one, else the type.
    static func display(type: QuotaWindowType, label: String?) -> String {
        if let label, !label.isEmpty { return label }
        return typeName(type)
    }

    /// Mid-sentence form: "weekly window", "Claude and GPT Models 5-hour window".
    static func phrase(of reading: AccountPressureReading) -> String {
        let type = typeName(reading.window).lowercased()
        if let label = reading.windowLabel, !label.isEmpty { return "\(label) \(type) window" }
        return "\(type) window"
    }

    /// "Claude Code · account-1", or just "Cursor" for a provider without accounts.
    static func owner(of reading: AccountPressureReading) -> String {
        reading.namesAccount ? "\(reading.providerName) · \(reading.accountLabel)" : reading.providerName
    }
}

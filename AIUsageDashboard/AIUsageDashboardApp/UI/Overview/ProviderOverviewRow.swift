import SwiftUI
import AIUsageDashboardCore

/// Static helpers that outlived the dead `ProviderOverviewRow` view (t04 D22).
/// Connections, Overview quota cells, and the drill-in countdown still call these.
enum ProviderOverviewRow {
    /// Providers that have a live-quota connector. Local-only agents (codex, cline)
    /// do not get an "enable" affordance.
    static let connectableProviders: Set<ProviderID> = [.claudeCode, .cursor, .antigravity]

    /// The UserDefaults key the Connections toggle writes, or `nil` for local-only providers.
    static func liveEnabledKey(for providerID: ProviderID) -> String? {
        switch providerID {
        case .claudeCode: return "claudeNetworkUsageEnabled"
        case .cursor: return "cursorNetworkUsageEnabled"
        case .antigravity: return "antigravityOnlineQuotaEnabled"
        default: return nil
        }
    }

    /// Bar emphasis by how close a window is to its ceiling. Accent only at ≥90.
    static func thresholdColor(_ usedPercent: Double) -> Color {
        if usedPercent >= 90 { return PadzyTheme.accent }
        if usedPercent >= 70 { return PadzyTheme.accent.opacity(0.6) }
        return PadzyTheme.ink
    }

    /// Days-out windows read as "4d 9h"; nearer ones as "HH:MM:SS" / "MM:SS".
    static func format(until date: Date, now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "NOW" }
        let totalSeconds = Int(interval)
        let totalHours = totalSeconds / 3600
        if totalHours >= 24 {
            return "\(totalHours / 24)d \(totalHours % 24)h"
        }
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if totalHours > 0 {
            return String(format: "%02d:%02d:%02d", totalHours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

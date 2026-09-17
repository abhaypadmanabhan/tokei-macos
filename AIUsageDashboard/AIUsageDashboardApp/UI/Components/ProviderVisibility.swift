import SwiftUI
import AIUsageDashboardCore

/// Per-provider "hide from the chip strip/menu bar" state. UI-only (`UserDefaults`
/// directly, no Core involvement) — separate from the Cursor network toggle,
/// which is a single fixed key the Cursor connector itself reads.
enum ProviderVisibility {
    static func key(for providerID: ProviderID) -> String {
        "provider_hidden_\(providerID.rawValue)"
    }

    static func isHidden(_ providerID: ProviderID, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key(for: providerID))
    }

    static func setHidden(_ hidden: Bool, for providerID: ProviderID, defaults: UserDefaults = .standard) {
        defaults.set(hidden, forKey: key(for: providerID))
    }

    /// Drop snapshots the user has hidden. Every token aggregate the dashboard
    /// prints goes through here, so a hidden agent can't keep feeding a headline
    /// it no longer appears in — the Overview hero and the `01 / OVERVIEW` tab
    /// pill both counted hidden agents while the pane said "no agents linked".
    static func visible(_ snapshots: [ProviderSnapshot], defaults: UserDefaults = .standard) -> [ProviderSnapshot] {
        snapshots.filter { !isHidden($0.providerID, defaults: defaults) }
    }
}

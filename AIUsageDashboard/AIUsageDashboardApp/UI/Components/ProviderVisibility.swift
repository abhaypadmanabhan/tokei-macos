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

/// Settings row: a "SHOW <PROVIDER>" switch. One `@AppStorage` instance per row,
/// keyed dynamically at init so a single reusable view covers all providers.
struct ProviderVisibilityToggleRow: View {
    let providerID: ProviderID
    let displayName: String
    @AppStorage private var isHidden: Bool

    init(providerID: ProviderID, displayName: String) {
        self.providerID = providerID
        self.displayName = displayName
        _isHidden = AppStorage(wrappedValue: false, ProviderVisibility.key(for: providerID))
    }

    var body: some View {
        Toggle(isOn: Binding(get: { !isHidden }, set: { isHidden = !$0 })) {
            Text("SHOW \(displayName.uppercased())")
                .font(.mono(size: 12))
                .foregroundColor(PadzyTheme.ink)
        }
        .toggleStyle(.padzy)
    }
}

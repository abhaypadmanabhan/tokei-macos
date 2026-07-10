import SwiftUI
import AIUsageDashboardCore

/// Per-provider "hide from sidebar/menu bar" state. UI-only (`UserDefaults`
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

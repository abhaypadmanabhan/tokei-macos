import Foundation

/// What the system menu-bar item renders next to the Tokei mark. UI-only
/// preference (persisted via `@AppStorage`), selectable in Settings (#38/#40).
///
/// One aggregate value regardless of how many providers are connected, so the
/// status item stays a fixed, compact width no matter the account count.
enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    /// Today's total tokens across available providers (the original behaviour).
    case todayTokens
    /// The single tightest quota window's % across all providers — the number
    /// that actually constrains you right now (#38).
    case tightestPercent
    /// Just the mark. Tightest for a crowded menu bar.
    case iconOnly

    var id: String { rawValue }

    /// AppStorage key shared by the label view and the Settings picker.
    static let storageKey = "menuBarDisplayMode"

    /// Picker row label.
    var title: String {
        switch self {
        case .todayTokens: return "Today's tokens"
        case .tightestPercent: return "Tightest quota %"
        case .iconOnly: return "Icon only"
        }
    }

    /// One-line hint under the picker explaining the choice.
    var hint: String {
        switch self {
        case .todayTokens: return "Total tokens used today across your agents."
        case .tightestPercent: return "The fullest quota window — how close to a wall you are."
        case .iconOnly: return "Mark only, for the most compact menu bar."
        }
    }
}

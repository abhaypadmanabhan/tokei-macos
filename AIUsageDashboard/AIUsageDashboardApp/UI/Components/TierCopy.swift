import Foundation
import AIUsageDashboardCore

/// The tier as words. Kept in the UI layer on purpose (the frozen §4 contract carries no
/// presentation strings) and in its own Foundation-only file so the burn copy that names
/// tiers ("Tier up: Goblin mode") is tested in the Core bundle.
extension MaxxerTier {
    /// The tier as a word, sentence case.
    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .warming: return "Warming"
        case .breakEven: return "Break-even"
        case .maxxing: return "Maxxing"
        case .goblinMode: return "Goblin mode"
        }
    }

    /// One line explaining what the tier means in plan-value terms.
    var blurb: String {
        switch self {
        case .idle: return "Barely touching what you pay for."
        case .warming: return "Below break-even on your plans."
        case .breakEven: return "Your plans have paid for themselves."
        case .maxxing: return "Well past break-even."
        case .goblinMode: return "5× your plan cost or better."
        }
    }
}

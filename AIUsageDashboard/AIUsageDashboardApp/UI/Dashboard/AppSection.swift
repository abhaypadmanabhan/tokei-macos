import SwiftUI
import AIUsageDashboardCore

/// The three plain tabs at the top of the dashboard: OVERVIEW / VALUE / AGENTS.
/// The mockup dropped the numbered `NN /` kickers and the per-tab live number —
/// each tab is now pure navigation, a plain word with a 2px accent tick when active.
enum DashboardTab: String, CaseIterable, Identifiable {
    case overview
    case value
    case agents

    var id: String { rawValue }

    /// Plain tab label — the mockup's word, no numbered kicker.
    var label: String {
        switch self {
        case .overview: return "Overview"
        case .value: return "Value"
        case .agents: return "Agents"
        }
    }

    var section: AppSection {
        switch self {
        case .overview: return .overview
        case .value: return .value
        case .agents: return .connections
        }
    }

    /// Spoken label — identical to the visible label now that the kicker is gone.
    var accessibilityName: String { label }

    /// Neighbours for left/right arrow navigation. Deliberately non-wrapping, so
    /// holding an arrow key stops at the end of the strip instead of cycling.
    var next: DashboardTab? {
        switch self {
        case .overview: return .value
        case .value: return .agents
        case .agents: return nil
        }
    }

    var previous: DashboardTab? {
        switch self {
        case .overview: return nil
        case .value: return .overview
        case .agents: return .value
        }
    }
}

/// The destinations the dashboard pane routes between. Held as local `@State` in
/// `DashboardView`; `Core` stays untouched.
///
/// Three of these are *tab-owned* (`.overview`, `.value`, and `.connections` — the
/// Agents tab). The remaining one (`.provider`) is a drill-in pane that replaces the
/// tab content and renders a back affordance instead of a tab highlight. Settings is
/// no longer a section — it is a right-hand drawer overlaid on the whole window,
/// driven directly by `viewModel.showingSettings`.
enum AppSection: Equatable {
    case overview
    /// Plan value vs. API-equivalent cost, and lifetime totals (#23 / #41).
    case value
    case provider(ProviderID)
    /// The Agents tab's content (the former Connections drill-in). Owned by the
    /// `.agents` tab, so it is NOT a drill-in.
    case connections

    /// The tab that owns this section, or `nil` for the drill-in pane (`.provider`).
    var tab: DashboardTab? {
        switch self {
        case .overview: return .overview
        case .value: return .value
        case .connections: return .agents
        case .provider: return nil
        }
    }

    /// True when this pane replaced the tab content and needs a back affordance.
    var isDrillIn: Bool { tab == nil }

    /// Whether the shared time-range control actually governs this pane. Overview
    /// analytics and the provider detail are both ranged by `viewModel.range`;
    /// Value is month-to-date, and Agents has no series at all, so the control is
    /// hidden there rather than shown as a dead knob.
    var usesTimeRange: Bool {
        switch self {
        case .overview, .provider: return true
        case .value, .connections: return false
        }
    }
}

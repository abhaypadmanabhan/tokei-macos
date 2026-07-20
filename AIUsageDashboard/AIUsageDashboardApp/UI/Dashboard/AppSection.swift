import SwiftUI
import AIUsageDashboardCore

/// The two in-content tabs at the top of the dashboard. They replace the former
/// sidebar's OVERVIEW / VALUE rows: same two destinations, no 230pt of chrome.
///
/// Each pill also carries a live stat, so the tab strip doubles as the top-level
/// KPI row rather than being pure navigation — which is what lets the Overview's
/// old "Value" summary card be deleted without losing the number.
enum DashboardTab: String, CaseIterable, Identifiable {
    case overview
    case value

    var id: String { rawValue }

    /// Numbered mono kicker (`01 / OVERVIEW`) — the tab label itself.
    var kicker: String {
        switch self {
        case .overview: return "01 / OVERVIEW"
        case .value: return "02 / VALUE"
        }
    }

    var section: AppSection {
        switch self {
        case .overview: return .overview
        case .value: return .value
        }
    }

    /// Spoken label — the kicker's `01 /` prefix is decoration to VoiceOver.
    var accessibilityName: String {
        switch self {
        case .overview: return "Overview"
        case .value: return "Value"
        }
    }

    /// Neighbours for left/right arrow navigation. Deliberately non-wrapping, so
    /// holding an arrow key stops at the end of the strip instead of cycling.
    var next: DashboardTab? {
        switch self {
        case .overview: return .value
        case .value: return nil
        }
    }

    var previous: DashboardTab? {
        switch self {
        case .overview: return nil
        case .value: return .overview
        }
    }
}

/// The five destinations the dashboard pane routes between. Held as local
/// `@State` in `DashboardView`; `Core` stays untouched.
///
/// This local state is the source of truth for navigation. `viewModel.showingSettings`
/// is reconciled in one direction each way, not a true two-way binding: selecting a
/// section writes the flag (`true` only for `.settings`, `false` otherwise), and an
/// external RISING edge of the flag (e.g. the menu-bar Settings action) routes the
/// pane to `.settings`. Clearing the flag never changes the section.
///
/// Two of the five are *tabbed* (`.overview`, `.value`); the other three replace
/// the tab content and are entered by drilling in — a provider chip, a Connect
/// action, or the gear — so each of them renders a back affordance instead of a
/// tab highlight.
enum AppSection: Equatable {
    case overview
    /// Plan value vs. API-equivalent cost, and lifetime totals (#23 / #41).
    case value
    case provider(ProviderID)
    case settings
    case connections

    /// The tab that owns this section, or `nil` for the three drill-in panes.
    var tab: DashboardTab? {
        switch self {
        case .overview: return .overview
        case .value: return .value
        case .provider, .settings, .connections: return nil
        }
    }

    /// True when this pane replaced the tab content and needs a back affordance.
    var isDrillIn: Bool { tab == nil }

    /// Whether the shared time-range control actually governs this pane. Overview
    /// analytics and the provider detail are both ranged by `viewModel.range`;
    /// Value is month-to-date and Settings/Connections have no series at all, so
    /// the control is hidden there rather than shown as a dead knob.
    var usesTimeRange: Bool {
        switch self {
        case .overview, .provider: return true
        case .value, .settings, .connections: return false
        }
    }

    /// Whether the provider chip strip belongs on this pane. Overview, Value and
    /// the provider drill-in are all provider-scoped; Settings and Connections
    /// are not, so the strip is suppressed there.
    var showsProviderChips: Bool {
        switch self {
        case .overview, .value, .provider: return true
        case .settings, .connections: return false
        }
    }
}

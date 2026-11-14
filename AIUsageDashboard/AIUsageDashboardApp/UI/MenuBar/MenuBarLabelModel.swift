import Combine
import Foundation
import Observation
import AIUsageDashboardCore

/// Exactly what the status-item label shows, and nothing else.
///
/// Why it exists (WP-C AC 6, measured 2026-11-14): the label used to hold the whole
/// `DashboardViewModel`, an `ObservableObject`, so every `@Published` write anywhere (a tab
/// switch's `showingSettings = false`, each sync's loading flags) re-rendered it, and on this
/// macOS every label render makes `NSStatusItem` redraw its replicant snapshot on the main
/// thread. In a Time Profiler pass over tab switching that redraw was the largest block inside
/// the main-thread stalls. This model re-derives the label's values after each view model
/// change and assigns only the ones that differ, so the label (and the status item) redraw only
/// when what it shows changes.
@MainActor
@Observable
final class MenuBarLabelModel {
    private(set) var todayTotal = 0
    private(set) var todayIsUnknown = false
    private(set) var tightestPercent: Double?
    /// Only derived while the menu bar shows the lifetime total.
    private(set) var lifetimeTokens: Int?
    private(set) var isLoading = false

    @ObservationIgnored private weak var viewModel: DashboardViewModel?
    @ObservationIgnored private var subscriptions = Set<AnyCancellable>()

    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
        refresh()
        // `objectWillChange` fires before the write lands; hop one turn of the main queue so
        // the derived values read the new state.
        viewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
            .store(in: &subscriptions)
        // Hidden agents and the display mode live in UserDefaults.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
            .store(in: &subscriptions)
    }

    func refresh() {
        guard let viewModel else { return }
        update(\.todayTotal, viewModel.menuBarTodayTotal)
        update(\.todayIsUnknown, viewModel.todayIsUnknown)
        update(\.tightestPercent, viewModel.tightestAccountPressure?.usedPercent)
        update(\.isLoading, viewModel.isLoading)
        let mode = MenuBarDisplayMode(rawValue: UserDefaults.standard.string(forKey: MenuBarDisplayMode.storageKey) ?? "")
        if mode == .lifetime {
            let hidden = Set(ProviderID.allCases.filter { ProviderVisibility.isHidden($0) })
            update(\.lifetimeTokens, MaxxerMath.lifetimeTotal(in: viewModel.snapshots, hiddenProviders: hidden)?.tokens)
        } else {
            update(\.lifetimeTokens, nil)
        }
    }

    /// Assigns only a changed value: an `@Observable` write notifies even when equal.
    private func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<MenuBarLabelModel, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
}

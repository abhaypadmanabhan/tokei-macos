import SwiftUI
import AIUsageDashboardCore

/// The system menu-bar item's label (the always-visible status content), driven
/// by `MenuBarDisplayMode` (#40 space-efficient item, #38 tightest-% mode).
///
/// Deliberately renders ONE aggregate value — never a per-provider list — so the
/// item stays a fixed, compact width whether one agent or six are connected
/// (graceful degradation). Numerics use monospaced digits at the native menu-bar
/// size.
///
/// The mark is the DYNAMIC `TokeiStatusIcon`: the logo's four meter bars fill
/// with the tightest window's burn and shift ink → accent as the limit nears
/// (template while monochrome so it adapts to the bar; colored once the accent
/// IS the state). While a sync is in flight a small circular spinner trails the
/// value (static frame under Reduce Motion).
struct MenuBarLabel: View {
    @EnvironmentObject private var viewModel: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(MenuBarDisplayMode.storageKey)
    private var rawMode = MenuBarDisplayMode.todayTokens.rawValue

    /// One spinner frame every 0.15 s — the cadence the ring was tuned at.
    private static let spinnerTick: TimeInterval = 0.15

    /// Current spinner frame. Advanced by `spinnerLoop` ONLY while a sync is in
    /// flight; a plain `Image` reads it. Deliberately NOT a `TimelineView`: this
    /// view is a `MenuBarExtra` label, which SwiftUI snapshots into the status
    /// item — a `TimelineView`'s self-driving clock breaks that render and the
    /// item never appears. A `@State`-backed `Image` (the pattern shipped 0.4.0)
    /// renders reliably; the async loop just gives us the battery win of no
    /// ticking source at idle.
    @State private var spinnerPhase = 0

    private var mode: MenuBarDisplayMode {
        MenuBarDisplayMode(rawValue: rawMode) ?? .todayTokens
    }

    /// The constraining reading across every provider — what the bars fill by.
    private var tightest: Utilization? {
        MaxxerMath.tightestWindow(in: viewModel.utilization)
    }

    private var mark: some View {
        Image(nsImage: TokeiStatusIcon.image(percent: tightest?.usedPercent))
    }

    @ViewBuilder
    private var syncSpinner: some View {
        if viewModel.isLoading {
            Image(nsImage: TokeiStatusIcon.spinnerImage(phase: reduceMotion ? 0 : spinnerPhase))
                .accessibilityLabel("Syncing")
        }
    }

    /// Ticks the spinner while `isLoading`, then stops. Bound via `.task(id:)` to
    /// `isLoading`, so the loop is created when a sync starts and cancelled the
    /// instant it ends — nothing wakes the main runloop at idle (the 0.4.0
    /// `Timer.publish(…).autoconnect()` ran ~6.6×/s for the whole app lifetime).
    private func spinnerLoop() async {
        guard viewModel.isLoading, !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(Self.spinnerTick * 1_000_000_000))
            if Task.isCancelled { break }
            spinnerPhase = (spinnerPhase + 1) % TokeiStatusIcon.spinnerPhases
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            mark

            switch mode {
            case .iconOnly:
                EmptyView()

            case .todayTokens:
                Text(TokenFormatter.format(viewModel.menuBarTodayTotal))
                    .monospacedDigit()

            case .tightestPercent:
                if let tightest {
                    Text("\(Int(round(tightest.usedPercent)))%")
                        .monospacedDigit()
                } else {
                    // No live quota anywhere yet — honest placeholder, never a "0%".
                    Text("—")
                }
            }

            syncSpinner
        }
        .task(id: viewModel.isLoading) {
            await spinnerLoop()
        }
    }
}

import SwiftUI
import AIUsageDashboardCore

/// The system menu-bar item's label (the always-visible status content), driven
/// by `MenuBarDisplayMode` (#40 space-efficient item, #38 tightest-% mode).
///
/// Deliberately renders ONE aggregate value — never a per-provider list — so the
/// item stays a fixed, compact width whether one agent or six are connected
/// (graceful degradation). Numerics use monospaced digits at the native menu-bar
/// size; the mark is a template image that adapts to the bar's light/dark
/// appearance. The item stays monochrome for legibility across wallpapers — the
/// near-limit accent *state* lives in the popover, not the status text.
struct MenuBarLabel: View {
    @EnvironmentObject private var viewModel: DashboardViewModel

    @AppStorage(MenuBarDisplayMode.storageKey)
    private var rawMode = MenuBarDisplayMode.todayTokens.rawValue

    private var mode: MenuBarDisplayMode {
        MenuBarDisplayMode(rawValue: rawMode) ?? .todayTokens
    }

    private var mark: some View { Image(nsImage: TokeiMark.menuBarImage) }

    var body: some View {
        switch mode {
        case .iconOnly:
            mark

        case .todayTokens:
            HStack(spacing: 5) {
                mark
                Text(TokenFormatter.format(viewModel.menuBarTodayTotal))
                    .monospacedDigit()
            }

        case .tightestPercent:
            HStack(spacing: 5) {
                mark
                if let tightest = MaxxerMath.tightestWindow(in: viewModel.utilization) {
                    Text("\(Int(round(tightest.usedPercent)))%")
                        .monospacedDigit()
                } else {
                    // No live quota anywhere yet — honest placeholder, never a "0%".
                    Text("—")
                }
            }
        }
    }
}

import SwiftUI
import AIUsageDashboardCore

// Previews for `OverviewView`, kept beside the view rather than inside it so the view
// file stays the surface itself. Fixture builders are file-private to this file.

// MARK: - Previews

@MainActor
private func mockViewModel(_ snapshots: [ProviderSnapshot]) -> DashboardViewModel {
    for id in ProviderID.allCases { ProviderVisibility.setHidden(false, for: id) }
    let model = DashboardViewModel()
    model.snapshots = snapshots
    return model
}

private func previewDailyTotals(days: Int) -> [Date: Int] {
    let values = [4_200_000, 9_800_000, 7_400_000, 15_200_000, 11_100_000,
                  18_600_000, 9_300_000, 21_400_000, 16_800_000, 12_500_000]
    let today = Calendar.current.startOfDay(for: Date())
    var totals: [Date: Int] = [:]
    for offset in 0..<days {
        if let day = Calendar.current.date(byAdding: .day, value: -offset, to: today) {
            totals[day] = values[offset % values.count]
        }
    }
    return totals
}

private func previewHourlyTotals() -> [Date: Int] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    var totals: [Date: Int] = [:]
    for daysBack in 0..<7 {
        for hour in [9, 11, 14, 16, 21] {
            if let day = calendar.date(byAdding: .day, value: -daysBack, to: today),
               let slot = calendar.date(byAdding: .hour, value: hour, to: day) {
                totals[slot] = (daysBack + 1) * (hour % 5 + 1) * 120_000
            }
        }
    }
    return totals
}

@MainActor
private func mockSnapshot(
    _ id: ProviderID,
    name: String,
    plan: String? = nil,
    windows: [QuotaWindow] = [],
    today: TokenUsage = .unavailable,
    dailyTotals: [Date: Int]? = nil,
    hourlyTotals: [Date: Int]? = nil
) -> ProviderSnapshot {
    ProviderSnapshot(
        providerID: id,
        displayName: name,
        authStatus: .authenticated,
        quotaWindows: windows,
        todayUsage: today,
        weekUsage: .unavailable,
        warnings: plan.map { [ProviderWarning(message: "Plan: \($0)", level: .info)] } ?? [],
        dailyTotals: dailyTotals,
        hourlyTotals: hourlyTotals
    )
}

@MainActor
private func window(_ id: ProviderID, _ type: QuotaWindowType, used: Double, inHours: Double) -> QuotaWindow {
    QuotaWindow(
        providerID: id, type: type, used: used, limit: 100,
        resetAt: Date().addingTimeInterval(inHours * 3600),
        confidence: .providerReported, source: "preview"
    )
}

#Preview("Full · live + tokens + hourly") {
    OverviewView()
        .environmentObject(mockViewModel([
            mockSnapshot(.claudeCode, name: "Claude Code", plan: "Max · yearly",
                         windows: [window(.claudeCode, .weekly, used: 95, inHours: 105),
                                   window(.claudeCode, .session, used: 40, inHours: 3)],
                         today: TokenUsage(inputTokens: 12_400_000, outputTokens: 1_900_000,
                                           cacheReadTokens: 48_100_000, cacheCreationTokens: 3_200_000,
                                           confidence: .exact),
                         dailyTotals: previewDailyTotals(days: 14),
                         hourlyTotals: previewHourlyTotals()),
            mockSnapshot(.cursor, name: "Cursor", plan: "Pro",
                         windows: [window(.cursor, .monthly, used: 78, inHours: 11)]),
            mockSnapshot(.antigravity, name: "Antigravity",
                         windows: [window(.antigravity, .fiveHour, used: 32, inHours: 3)]),
            mockSnapshot(.codex, name: "Codex",
                         windows: [window(.codex, .weekly, used: 12, inHours: 60)],
                         today: TokenUsage(inputTokens: 3_800_000, outputTokens: 700_000, confidence: .estimated),
                         dailyTotals: previewDailyTotals(days: 7))
        ]))
        .frame(width: 980, height: 1250)
        .background(PadzyTheme.ground)
}

#Preview("Narrow 640 · no hourly") {
    OverviewView()
        .environmentObject(mockViewModel([
            mockSnapshot(.claudeCode, name: "Claude Code", plan: "Max · yearly",
                         windows: [window(.claudeCode, .weekly, used: 88, inHours: 105)],
                         today: TokenUsage(inputTokens: 5_100_000, outputTokens: 900_000, confidence: .exact),
                         dailyTotals: previewDailyTotals(days: 7)),
            mockSnapshot(.cursor, name: "Cursor", plan: "Pro")
        ]))
        .frame(width: 640, height: 1150)
        .background(PadzyTheme.ground)
}

#Preview("Blank canvas") {
    for id in ProviderID.allCases { ProviderVisibility.setHidden(true, for: id) }
    return OverviewView(onAddAgent: {})
        .environmentObject(mockViewModel([]))
        .frame(width: 720, height: 520)
        .background(PadzyTheme.ground)
}

#Preview("All unavailable · empty analytics") {
    OverviewView()
        .environmentObject(mockViewModel([
            mockSnapshot(.claudeCode, name: "Claude Code"),
            mockSnapshot(.cursor, name: "Cursor"),
            mockSnapshot(.antigravity, name: "Antigravity")
        ]))
        .frame(width: 760, height: 1000)
        .background(PadzyTheme.ground)
}

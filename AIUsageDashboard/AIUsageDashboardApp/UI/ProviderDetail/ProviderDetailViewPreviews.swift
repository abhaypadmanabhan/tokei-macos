import SwiftUI
import AIUsageDashboardCore

// Previews live beside the view rather than inside it, so the view file stays the surface
// itself — same arrangement as `OverviewViewPreviews.swift`.

private func previewTrend(days: Int) -> [(date: Date, tokens: Int)] {
    let values = [4_200_000, 9_800_000, 7_400_000, 15_200_000, 11_100_000,
                  18_600_000, 9_300_000, 21_400_000, 16_800_000, 12_500_000]
    let today = Calendar.current.startOfDay(for: Date())
    return (0..<days).map { offset in
        let daysBack = days - 1 - offset
        return (
            date: Calendar.current.date(byAdding: .day, value: -daysBack, to: today) ?? today,
            tokens: values[offset % values.count]
        )
    }
}

private func previewSnapshot() -> ProviderSnapshot {
    ProviderSnapshot(
        providerID: .claudeCode,
        displayName: "Claude Code",
        authStatus: .authenticated,
        quotaWindows: [
            QuotaWindow(providerID: .claudeCode, type: .weekly, used: 46, limit: 100,
                        resetAt: Date().addingTimeInterval(3 * 86_400 + 14 * 3600),
                        confidence: .providerReported, source: "preview", label: "Weekly"),
            QuotaWindow(providerID: .claudeCode, type: .fiveHour, used: 22, limit: 100,
                        resetAt: Date().addingTimeInterval(2 * 3600 + 41 * 60),
                        confidence: .providerReported, source: "preview", label: "5-hour")
        ],
        todayUsage: TokenUsage(inputTokens: 41_200_000, outputTokens: 25_500_000,
                               cacheReadTokens: 402_800_000, cacheCreationTokens: 63_500_000,
                               confidence: .providerReported),
        weekUsage: TokenUsage(inputTokens: 300_000_000, outputTokens: 60_000_000, confidence: .providerReported)
    )
}

#Preview("Full metrics") {
    ProviderDetailView(
        snapshot: previewSnapshot(),
        trend: previewTrend(days: 14),
        peakHour: (hour: 15, tokens: 6_800_000),
        lastSyncedAt: Date(),
        isRouteTarget: false,
        planLabel: "$200/mo · 2× Max accounts"
    )
    .frame(width: 900, height: 1200)
}

#Preview("Plan-only · credits") {
    ProviderDetailView(
        snapshot: ProviderSnapshot(
            providerID: .antigravity,
            displayName: "Antigravity",
            authStatus: .authenticated,
            quotaWindows: [
                QuotaWindow(providerID: .antigravity, type: .credits, used: 340, limit: 500,
                            confidence: .providerReported, source: "preview"),
                QuotaWindow(providerID: .antigravity, type: .weekly, used: 71, limit: 100,
                            resetAt: Date().addingTimeInterval(4 * 86_400),
                            confidence: .providerReported, source: "preview", label: "Gemini · Weekly")
            ],
            todayUsage: .unavailable,
            weekUsage: .unavailable
        ),
        lastSyncedAt: Date(),
        isRouteTarget: true,
        planLabel: "$5/mo · Google student"
    )
    .frame(width: 720, height: 900)
}

/// Two accounts with genuinely different daily shapes and different quota — the machine this
/// was built for. `default` spends more but has the headroom; `account-1` is the 88% the card
/// used to hide behind a 50%.
private func previewAccounts(_ count: Int, days: Int) -> [ProviderAccountUsage] {
    let today = Calendar.current.startOfDay(for: Date())
    let shapes: [[Int]] = [
        [12_000_000, 31_000_000, 8_400_000, 44_000_000, 27_000_000, 51_000_000, 19_000_000],
        [4_100_000, 3_200_000, 9_800_000, 2_400_000, 14_000_000, 6_100_000, 11_200_000],
        [900_000, 2_100_000, 400_000, 3_300_000, 1_200_000, 2_800_000, 700_000]
    ]
    let peaks: [Double] = [50, 88, 31]
    return (0..<count).map { index in
        var totals: [Date: Int] = [:]
        for back in 0..<days {
            let date = Calendar.current.date(byAdding: .day, value: -back, to: today) ?? today
            totals[date] = shapes[index % shapes.count][back % 7]
        }
        return ProviderAccountUsage(
            id: index == 0 ? "/Users/preview/.claude" : "/Users/preview/.claude-account-\(index)",
            label: index == 0 ? "default" : "account-\(index)",
            quotaWindows: [
                QuotaWindow(providerID: .claudeCode, type: .weekly, used: peaks[index % peaks.count],
                            limit: 100, resetAt: Date().addingTimeInterval(3 * 86_400),
                            confidence: .providerReported, source: "preview", label: "Weekly")
            ],
            todayUsage: TokenUsage(inputTokens: 1_000_000, outputTokens: 400_000,
                                   confidence: .providerReported),
            dailyTotals: totals,
            configDirectories: index == 0
                ? ["/Users/preview/.claude", "/Users/preview/.claude-account-2"]
                : ["/Users/preview/.claude-account-\(index)"],
            unreadableDirectories: []
        )
    }
}

private func previewMultiAccountSnapshot(_ count: Int, unreadable: Bool = false) -> ProviderSnapshot {
    var accounts = previewAccounts(count, days: 14)
    if unreadable, let first = accounts.first {
        accounts[0] = ProviderAccountUsage(
            id: first.id, label: first.label, quotaWindows: first.quotaWindows,
            todayUsage: first.todayUsage, dailyTotals: first.dailyTotals,
            configDirectories: first.configDirectories,
            unreadableDirectories: ["/Users/preview/.claude-account-2"]
        )
    }
    let base = previewSnapshot()
    return ProviderSnapshot(
        providerID: base.providerID,
        displayName: base.displayName,
        authStatus: base.authStatus,
        quotaWindows: base.quotaWindows,
        todayUsage: base.todayUsage,
        weekUsage: base.weekUsage,
        accounts: accounts
    )
}

#Preview("Two accounts") {
    ProviderDetailView(
        snapshot: previewMultiAccountSnapshot(2),
        trend: previewTrend(days: 14),
        peakHour: (hour: 15, tokens: 6_800_000),
        lastSyncedAt: Date(),
        planLabel: "$200/mo \u{00B7} 2\u{00D7} Max accounts"
    )
    .frame(width: 980, height: 1200)
}

#Preview("Three accounts · narrow") {
    ProviderDetailView(
        snapshot: previewMultiAccountSnapshot(3, unreadable: true),
        trend: previewTrend(days: 14),
        lastSyncedAt: Date()
    )
    .frame(width: 640, height: 1300)
}

#Preview("Narrow 640") {
    ProviderDetailView(
        snapshot: previewSnapshot(),
        trend: previewTrend(days: 7),
        peakHour: (hour: 11, tokens: 4_100_000),
        lastSyncedAt: Date(),
        planLabel: "$200/mo · 2× Max accounts"
    )
    .frame(width: 640, height: 1200)
}

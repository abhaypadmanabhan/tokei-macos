import Foundation

extension DashboardViewModel {
    /// True while the saved numbers on screen were saved on an earlier day: their "today"
    /// figures describe that day, so a surface that cannot name the day (the menu-bar item,
    /// the popover) shows today's tokens as unknown until live numbers land.
    public var todayIsUnknown: Bool {
        guard showingSavedSnapshots else { return false }
        guard let saved = savedSnapshotsDate else { return true }
        return !analyticsCalendar.isDate(saved, inSameDayAs: now())
    }
}

/// Ages a snapshot saved by an earlier run before it is shown: any quota reading whose
/// reset has passed describes a window that already refilled, so it becomes an unknown
/// reading (no used share, no reset) rather than a confident stale number.
enum SavedSnapshotAging {
    static func expiringPastResets(_ snapshot: ProviderSnapshot, now: Date) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: snapshot.providerID,
            displayName: snapshot.displayName,
            authStatus: snapshot.authStatus,
            quotaWindows: snapshot.quotaWindows.map { expiring($0, now: now) },
            todayUsage: snapshot.todayUsage,
            weekUsage: snapshot.weekUsage,
            monthUsage: snapshot.monthUsage,
            lifetimeUsage: snapshot.lifetimeUsage,
            costUsage: snapshot.costUsage,
            warnings: snapshot.warnings,
            lastSyncedAt: snapshot.lastSyncedAt,
            dailyTotals: snapshot.dailyTotals,
            hourlyTotals: snapshot.hourlyTotals,
            dailyModelUsage: snapshot.dailyModelUsage,
            accounts: snapshot.accounts?.map { account in
                ProviderAccountUsage(
                    id: account.id,
                    accountID: account.accountID,
                    selector: account.selector,
                    label: account.label,
                    quotaWindows: account.quotaWindows.map { expiring($0, now: now) },
                    todayUsage: account.todayUsage,
                    dailyTotals: account.dailyTotals,
                    configDirectories: account.configDirectories,
                    unreadableDirectories: account.unreadableDirectories,
                    quotaStatus: account.quotaStatus,
                    quotaStatusDetail: account.quotaStatusDetail
                )
            },
            headlineAccountID: snapshot.headlineAccountID
        )
    }

    static func expiring(_ window: QuotaWindow, now: Date) -> QuotaWindow {
        guard let resetAt = window.resetAt, resetAt <= now else { return window }
        return QuotaWindow(
            providerID: window.providerID,
            type: window.type,
            confidence: .estimated,
            source: "Saved reading from before its reset",
            label: window.label,
            bucketKey: window.bucketKey,
            observedAt: window.observedAt,
            windowDuration: window.windowDuration
        )
    }
}

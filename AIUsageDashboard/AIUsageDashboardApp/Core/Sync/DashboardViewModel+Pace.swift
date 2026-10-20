import Foundation

// Pace read accessors (WP-3): used vs elapsed share of the window behind each live
// reading. Kept apart from `DashboardViewModel.swift` so the view model's own file stays
// the published state and its analytics; everything here is derived and read-only.

extension DashboardViewModel {
    /// Pace of the window behind `tightestAccountPressure`; `nil` when it has no honest pace.
    public var tightestAccountPace: QuotaPace? {
        tightestAccountPeak.flatMap { QuotaPace(window: $0.window, now: now()) }
    }

    /// Pace for a live reading, read off the window that produced it so it carries that
    /// window's reported length and follows `QuotaPace(window:now:)`'s rules (a reported
    /// `used` is required: a remaining-only reading gets no pace).
    public func pace(for utilization: Utilization) -> QuotaPace? {
        let source = snapshot(for: utilization.providerID)?.quotaWindows.first {
            $0.type == utilization.window
                && $0.resetAt == utilization.resetAt
                && UtilizationEngine.usedPercent(from: $0) == utilization.usedPercent
        }
        return source.flatMap { QuotaPace(window: $0, now: now()) }
    }

    /// The highest-used account window among visible providers; first seen wins a tie.
    var tightestAccountPeak: AccountPeak? {
        var best: AccountPeak?
        for snapshot in visibleSnapshots {
            for peak in accountPeaks(in: snapshot) {
                if let current = best, peak.reading.usedPercent <= current.reading.usedPercent { continue }
                best = peak
            }
        }
        return best
    }

    /// A reading and the window that produced it, so pace can be read off the same window.
    typealias AccountPeak = (reading: AccountPressureReading, window: QuotaWindow)

    private func accountPeaks(in snapshot: ProviderSnapshot) -> [AccountPeak] {
        if let accounts = snapshot.accounts, !accounts.isEmpty {
            return accounts.compactMap { account in
                guard let (window, peak) = peakWindow(account.quotaWindows) else { return nil }
                let reading = AccountPressureReading(
                    providerID: snapshot.providerID,
                    accountID: account.id,
                    accountLabel: account.label,
                    usedPercent: peak
                )
                return (reading, window)
            }
        }
        guard let (window, peak) = peakWindow(snapshot.quotaWindows) else { return [] }
        let reading = AccountPressureReading(
            providerID: snapshot.providerID,
            accountID: snapshot.providerID.rawValue,
            accountLabel: snapshot.displayName,
            usedPercent: peak
        )
        return [(reading, window)]
    }

    /// The highest-used non-credit window and its used %.
    private func peakWindow(_ windows: [QuotaWindow]) -> (QuotaWindow, Double)? {
        windows
            .filter { $0.type != .credits }
            .compactMap { window in UtilizationEngine.usedPercent(from: window).map { (window, $0) } }
            .max { $0.1 < $1.1 }
    }
}

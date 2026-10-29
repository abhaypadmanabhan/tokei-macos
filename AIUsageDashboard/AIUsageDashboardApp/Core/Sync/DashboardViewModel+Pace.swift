import Foundation

// Pace read accessors (WP-3): used vs elapsed share of the window behind each live
// reading. Kept apart from `DashboardViewModel.swift` so the view model's own file stays
// the published state and its analytics; everything here is derived and read-only.

extension DashboardViewModel {
    /// Pace of the window behind `tightestAccountPressure`; `nil` when it has no honest pace.
    public var tightestAccountPace: QuotaPace? {
        tightestAccountPeak.flatMap { QuotaPace(window: $0.window, now: now()) }
    }

    /// Per-window readings for gauges: `utilization` without credit balances (Claude's extra
    /// usage is dollars, never a percentage ceiling) and without readings whose reset has
    /// passed (that window already refilled; the number describes the old one).
    public var gaugeUtilizations: [Utilization] {
        let now = now()
        return utilization.filter { reading in
            reading.window != .credits && (reading.resetAt.map { $0 > now } ?? true)
        }
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

    /// Whether a window may be called "the tightest": a percentage gauge the provider
    /// reported live, not a credit balance and not past its reset.
    ///
    /// - A cached replay or a local estimate comes back `.estimated`; it is still drawn on
    ///   its own row, but it is not a current reading to headline.
    /// - Credits (Claude's extra-usage dollars) are a balance, never the binding limit.
    /// - A saved reading whose reset has passed describes a window that already refilled.
    public static func isEligibleReading(_ window: QuotaWindow, now: Date) -> Bool {
        guard window.type != .credits,
              window.confidence == .providerReported || window.confidence == .exact,
              UtilizationEngine.usedPercent(from: window) != nil else { return false }
        return window.resetAt.map { $0 > now } ?? true
    }

    /// The highest-used eligible account window among visible providers; first seen wins a tie.
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
                return (reading(snapshot, accountID: account.id, label: account.label, window, peak), window)
            }
        }
        guard let (window, peak) = peakWindow(snapshot.quotaWindows) else { return [] }
        let reading = reading(
            snapshot, accountID: snapshot.providerID.rawValue, label: snapshot.displayName, window, peak
        )
        return [(reading, window)]
    }

    private func reading(
        _ snapshot: ProviderSnapshot,
        accountID: String,
        label: String,
        _ window: QuotaWindow,
        _ usedPercent: Double
    ) -> AccountPressureReading {
        AccountPressureReading(
            providerID: snapshot.providerID,
            providerName: snapshot.displayName,
            accountID: accountID,
            accountLabel: label,
            usedPercent: usedPercent,
            window: window.type,
            windowLabel: window.label,
            resetAt: window.resetAt
        )
    }

    /// The highest-used eligible window and its used %.
    private func peakWindow(_ windows: [QuotaWindow]) -> (QuotaWindow, Double)? {
        let now = now()
        return windows
            .filter { Self.isEligibleReading($0, now: now) }
            .compactMap { window in UtilizationEngine.usedPercent(from: window).map { (window, $0) } }
            .max { $0.1 < $1.1 }
    }
}

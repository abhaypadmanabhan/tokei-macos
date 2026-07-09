import Foundation
import AIUsageDashboardCore

/// Pure math for the Token-Maxxer surface — pace against a linear burn and the
/// single tightest window across providers. No I/O, no clock, no SwiftUI: every
/// value is derived from arguments so the same inputs always yield the same
/// output, which is what makes it unit-testable from the Core test bundle even
/// though it physically lives under `UI/`.
///
/// It reads only the frozen `QuotaWindow`/`Utilization` shapes — it never mutates
/// Core state and holds no credentials (see the `Utilization` security invariant).
public enum MaxxerMath {

    // MARK: - Linear-pace verdict

    /// How actual consumption compares to a perfectly linear burn of the window.
    /// Positive-framed on purpose (token-maxxer voice: room to use, not scolding):
    /// - `.ahead`    — spent more than the elapsed fraction; burning fast.
    /// - `.onPace`   — within the tolerance band of linear pace.
    /// - `.headroom` — spent less than elapsed; budget to spare.
    public enum PaceVerdict: String, Sendable, Equatable {
        case ahead
        case onPace
        case headroom
    }

    /// The result of a pace computation for one quota window.
    public struct QuotaPace: Sendable, Equatable {
        /// Fraction of the window elapsed, 0…1 — where the expected-pace notch sits.
        public let elapsedFraction: Double
        /// Expected utilization at linear pace, 0…100 (`elapsedFraction * 100`).
        public let expectedPercent: Double
        /// `usedPercent - expectedPercent`, positive = ahead of linear.
        public let delta: Double
        public let verdict: PaceVerdict

        public init(elapsedFraction: Double, expectedPercent: Double, delta: Double, verdict: PaceVerdict) {
            self.elapsedFraction = elapsedFraction
            self.expectedPercent = expectedPercent
            self.delta = delta
            self.verdict = verdict
        }
    }

    /// The canonical span of a rolling quota window, used to place the elapsed-pace
    /// notch. `nil` for window types with no fixed linear span (a session, a credit
    /// balance, a per-model or lifetime total) — those degrade to "no pace" rather
    /// than inventing a denominator.
    ///
    /// Monthly is treated as 30 days: `resetAt` gives the window's END, and without
    /// the exact anchor a 30-day span is the honest linear approximation for a notch.
    public static func canonicalWindowDuration(for type: QuotaWindowType) -> TimeInterval? {
        switch type {
        case .fiveHour: return 5 * 3_600
        case .daily:    return 24 * 3_600
        case .weekly:   return 7 * 86_400
        case .monthly:  return 30 * 86_400
        case .session, .credits, .perModel, .lifetime:
            return nil
        }
    }

    /// Compute pace for a window against a linear burn.
    ///
    /// Returns `nil` (→ the UI shows "—", never crashes) when the window has no
    /// canonical span or no `resetAt` — i.e. when an expected-pace position is
    /// undefined. `elapsedFraction` is clamped to 0…1 so a reset just in the past
    /// or a clock skew can't push the notch off the bar.
    ///
    /// - Parameters:
    ///   - usedPercent: actual utilization 0…100 (already `used / limit`).
    ///   - windowType: the quota window type (drives the canonical span).
    ///   - resetAt: when the window refills; its span is `[resetAt - duration, resetAt]`.
    ///   - now: current instant (injected — no wall clock here).
    ///   - tolerance: half-width of the on-pace band in percentage points (default 5).
    public static func pace(
        usedPercent: Double,
        windowType: QuotaWindowType,
        resetAt: Date?,
        now: Date,
        tolerance: Double = 5
    ) -> QuotaPace? {
        guard let duration = canonicalWindowDuration(for: windowType), duration > 0,
              let resetAt else { return nil }

        let remaining = resetAt.timeIntervalSince(now)
        let elapsed = duration - remaining
        let elapsedFraction = min(1, max(0, elapsed / duration))
        let expectedPercent = elapsedFraction * 100
        let delta = usedPercent - expectedPercent

        let verdict: PaceVerdict
        if delta > tolerance {
            verdict = .ahead
        } else if delta < -tolerance {
            verdict = .headroom
        } else {
            verdict = .onPace
        }

        return QuotaPace(
            elapsedFraction: elapsedFraction,
            expectedPercent: expectedPercent,
            delta: delta,
            verdict: verdict
        )
    }

    // MARK: - Tightest window selection

    /// The single tightest (highest-utilization) window across every provider —
    /// the number that actually constrains you. `nil` when there is no live quota
    /// anywhere. Deterministic: on a tie the first-seen reading wins (stable input
    /// order → stable pick), so the menu bar never flickers between equals.
    public static func tightestWindow(in utilizations: [Utilization]) -> Utilization? {
        utilizations.reduce(nil) { current, candidate in
            guard let current else { return candidate }
            return candidate.usedPercent > current.usedPercent ? candidate : current
        }
    }
}

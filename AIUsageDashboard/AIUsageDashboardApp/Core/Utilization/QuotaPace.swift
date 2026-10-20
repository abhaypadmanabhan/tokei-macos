import Foundation

/// Used share of a quota window against the share of the window that has passed —
/// "am I spending faster or slower than the clock?". T3 Code's rule
/// (`packages/shared/src/usageLimits.ts`, `paceOf`): a ±5-point band around an even
/// burn, elapsed share clamped to 0…100.
///
/// Pure: every input is an argument, including `now`. `nil` means "no honest pace" —
/// the window length, the reset time or the used share is unknown, or the window is
/// not a percentage gauge — and surfaces then show nothing rather than a guess.
public struct QuotaPace: Sendable, Equatable {
    public enum State: String, Sendable, Equatable {
        /// Used more than the elapsed share: burning faster than the clock.
        case ahead
        /// Within the band of an even burn.
        case onPace
        /// Used less than the elapsed share: room left to use before the reset.
        case behind
    }

    /// Half-width of the on-pace band, in percentage points.
    public static let band: Double = 5

    /// Used share of the window, 0…100.
    public let usedPercent: Double
    /// Share of the window that has passed, 0…100 — where the elapsed tick sits.
    public let elapsedPercent: Double
    public let state: State

    /// Points between used and elapsed share; positive means ahead of the clock.
    public var delta: Double { usedPercent - elapsedPercent }

    /// The window's length: the provider-reported duration when there is one, else the
    /// length its type implies. Monthly, credit, lifetime and per-model windows have no
    /// fixed length (a month is 28–31 days and the anchor is unknown), so they get pace
    /// only when the provider reports the duration.
    public static func duration(for type: QuotaWindowType, reported: TimeInterval?) -> TimeInterval? {
        if let reported { return reported > 0 ? reported : nil }
        switch type {
        case .session, .fiveHour: return 5 * 3_600
        case .daily: return 24 * 3_600
        case .weekly: return 7 * 86_400
        case .monthly, .credits, .lifetime, .perModel: return nil
        }
    }

    /// Pace for a quota window. `nil` unless the window is a percentage gauge (a
    /// positive `limit` with a reported `used`, and not a credit balance) with a known
    /// length and reset time. A `remaining`-only window gets no pace: the drill-in
    /// gauge shows its usage as unknown, and pace must not claim more than the gauge.
    public init?(window: QuotaWindow, now: Date) {
        guard window.type != .credits,
              let used = window.used,
              let limit = window.limit, limit > 0 else { return nil }
        self.init(
            usedPercent: used / limit * 100,
            windowType: window.type,
            windowDuration: window.windowDuration,
            resetAt: window.resetAt,
            now: now
        )
    }

    /// Pace from the parts of a window. `usedPercent` is clamped to 0…100.
    public init?(
        usedPercent: Double?,
        windowType: QuotaWindowType,
        windowDuration: TimeInterval?,
        resetAt: Date?,
        now: Date
    ) {
        guard windowType != .credits,
              let usedPercent, usedPercent.isFinite,
              let resetAt,
              let duration = Self.duration(for: windowType, reported: windowDuration)
        else { return nil }

        let elapsed = (duration - resetAt.timeIntervalSince(now)) / duration * 100
        let used = min(100, max(0, usedPercent))
        self.usedPercent = used
        self.elapsedPercent = min(100, max(0, elapsed))

        // The band edge is on pace. `used / limit * 100` carries float noise (55 / 100 * 100
        // is 55.000000000000007), so compare with a tolerance far below any real reading.
        let gap = used - self.elapsedPercent
        let edge = Self.band + 1e-9
        if gap > edge {
            state = .ahead
        } else if gap < -edge {
            state = .behind
        } else {
            state = .onPace
        }
    }
}

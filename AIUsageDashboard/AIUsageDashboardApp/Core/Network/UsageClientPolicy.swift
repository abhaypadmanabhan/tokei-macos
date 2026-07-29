import Foundation

/// The two decisions every usage/quota client has to make identically, in one place.
///
/// Both were re-derived per client and both were re-derived wrong. `f725bac` fixed the
/// Claude client's retry ceiling (it slept its own 30s cap and then retried against an
/// arbitrarily long `Retry-After`) and gave `QuotaWindow` a structural `observedAt` — but
/// nothing stopped the *next* client from repeating either mistake, and the Cursor client
/// (same storm) and the Antigravity client (no `observedAt`, staleness spelled as a
/// `" (stale)"` string suffix) had already done exactly that.
///
/// Deliberately small: two free-function-shaped decisions and a value type. This is not a
/// transport abstraction — clients keep owning their own requests, cooldown files, and
/// error types.
public enum UsageClientPolicy {
    /// The longest a client is willing to sit in-process waiting out a 429.
    ///
    /// Beyond this we stop rather than sleep: the endpoint already said "back off", and
    /// sleeping a fixed ceiling before asking again just hammers it — which can deepen or
    /// extend the very cooldown we're reacting to.
    public static let maxRetrySleepInterval: TimeInterval = 30

    /// Ceiling on how old a cached reading may be and still be served at all.
    ///
    /// Was 7 days in every client, which let a week-old number stand in for live quota —
    /// and `RouteTargetPolicy` classifies `avoid` from *every* reading, trusted or not, so
    /// a week-old cache could still steer work. Two hours is the point past which no
    /// consumer has a use for the number.
    public static let maxStaleInterval: TimeInterval = 2 * 60 * 60

    /// What to do after a 429.
    public enum RateLimitAction: Equatable, Sendable {
        /// Wait this long, then make one more attempt.
        case sleepThenRetry(TimeInterval)
        /// Stop now and surface a rate-limit error carrying this `Retry-After`
        /// (`nil` when the server sent none). The caller records its cooldown.
        case giveUp(retryAfter: TimeInterval?)
    }

    /// The retry decision for one 429.
    ///
    /// - `retryAfter`: parsed `Retry-After`, `nil` when absent/unparseable.
    /// - `attempt`: 1-based attempt that just returned 429.
    /// - `maxAttempts`: total attempts the caller is willing to make.
    /// - `defaultCooldownInterval`: backoff to use when the server sent no `Retry-After`.
    ///
    /// A `Retry-After` longer than ``maxRetrySleepInterval`` gives up **immediately** —
    /// on the first attempt, without sleeping — because no amount of waiting we're
    /// prepared to do will satisfy it.
    public static func rateLimitAction(
        retryAfter: TimeInterval?,
        attempt: Int,
        maxAttempts: Int,
        defaultCooldownInterval: TimeInterval
    ) -> RateLimitAction {
        if let retryAfter, retryAfter > maxRetrySleepInterval {
            return .giveUp(retryAfter: retryAfter)
        }
        guard attempt < maxAttempts else {
            return .giveUp(retryAfter: retryAfter)
        }
        return .sleepThenRetry(min(retryAfter ?? defaultCooldownInterval, maxRetrySleepInterval))
    }

    /// Stamps when these numbers were actually observed.
    ///
    /// Call this on every path that produces a `QuotaWindow` from a live response — a
    /// window with no `observedAt` reads as "age unknown" to the recommendation engine,
    /// which is not the same as "fresh".
    public static func observed(_ windows: [QuotaWindow], at date: Date) -> [QuotaWindow] {
        windows.map { $0.withObservedAt(date) }
    }

    /// Marks windows replayed from a cache rather than fetched: confidence drops to
    /// `.estimated` and `observedAt` becomes the time the cache was written.
    ///
    /// Staleness is a number, not a string. Do **not** append `" (stale)"` to `source` —
    /// `source` names where a reading came from, and consumers cannot do date arithmetic
    /// on a suffix. (`ClaudeUsageClient` still writes that suffix for display
    /// compatibility; it is cosmetic there and carries `observedAt` alongside.)
    public static func replayedFromCache(_ windows: [QuotaWindow], observedAt: Date) -> [QuotaWindow] {
        windows.map { window in
            QuotaWindow(
                providerID: window.providerID,
                type: window.type,
                used: window.used,
                limit: window.limit,
                remaining: window.remaining,
                resetAt: window.resetAt,
                confidence: .estimated,
                source: window.source,
                label: window.label,
                bucketKey: window.bucketKey,
                observedAt: observedAt
            )
        }
    }
}

import Foundation

/// A single provider's live utilization for one quota window — "how much of this
/// plan's ceiling am I using right now."
///
/// This is the **denominator contract**: the unified shape every provider's live
/// quota collapses into, and the type the future Maxxer Score surface (issue #23)
/// binds to. Design it once, correctly, so downstream needs no breaking change.
///
/// SECURITY INVARIANT: this model holds **only** percentages, reset times, and a
/// plan label — never a token, bearer, csrf, or any credential. It is safe to log
/// and safe to persist (see `UtilizationCache`). Keep it that way.
public struct Utilization: Sendable, Identifiable, Equatable, Codable {
    /// Which provider this reading belongs to.
    public let providerID: ProviderID
    /// The quota window this percentage measures (session / fiveHour / daily /
    /// weekly / monthly / …). Reuses the existing, frozen `QuotaWindowType`.
    public let window: QuotaWindowType
    /// Fraction of the window's ceiling consumed, expressed 0…100. Never negative,
    /// never above 100 — the engine clamps.
    public let usedPercent: Double
    /// When this window's budget refills, if the provider reports it. Drives the
    /// cache's early expiry (a stale reading past its reset is worthless).
    public let resetAt: Date?
    /// The plan/tier label the reading was taken under (e.g. "Pro · yearly"), when
    /// the provider surfaces one. Purely descriptive.
    public let plan: String?
    /// How trustworthy the underlying number is, propagated from the source
    /// `QuotaWindow`.
    public let confidence: MetricConfidence
    /// Whether the percentage is a full reading or derived from partial data.
    public let coverage: UtilizationCoverage

    /// Stable identity: one utilization per provider × window.
    public var id: String { "\(providerID.rawValue)_\(window.rawValue)" }

    public init(
        providerID: ProviderID,
        window: QuotaWindowType,
        usedPercent: Double,
        resetAt: Date? = nil,
        plan: String? = nil,
        confidence: MetricConfidence,
        coverage: UtilizationCoverage = .complete
    ) {
        self.providerID = providerID
        self.window = window
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.plan = plan
        self.confidence = confidence
        self.coverage = coverage
    }
}

/// Completeness of a utilization reading (per-window) or of an aggregate.
///
/// - Per-`Utilization`: `.complete` when the percent came from a full used/limit
///   (or remaining/limit) reading; `.partial` when derived from incomplete data.
/// - Per-`AggregateUtilization`: `.complete` when every quota-bearing provider
///   contributed; `.partial` when some connected provider reported no usable quota
///   and was **omitted** (never zero-filled).
public enum UtilizationCoverage: String, Sendable, Equatable, CaseIterable, Codable {
    case complete
    case partial
}

/// The single "today's utilization across all plans" number the Maxxer Score
/// consumes, plus enough context to explain it honestly.
///
/// Definition: for each covered provider take its **peak** window utilization (the
/// tightest ceiling — how close to maxing that plan you are), then average those
/// peaks across providers. Averaging per-provider peaks answers "across my plans,
/// how maxed am I," and is robust to providers exposing different window types.
public struct AggregateUtilization: Sendable, Equatable, Codable {
    /// The cross-plan utilization, 0…100.
    public let usedPercent: Double
    /// Providers that contributed a reading, in stable order — makes the number
    /// explainable ("based on cursor, antigravity").
    public let coveredProviders: [ProviderID]
    /// `.partial` when some quota-bearing provider reported nothing usable and was
    /// omitted from the mean.
    public let coverage: UtilizationCoverage
    /// The most conservative confidence among contributors.
    public let confidence: MetricConfidence

    public init(
        usedPercent: Double,
        coveredProviders: [ProviderID],
        coverage: UtilizationCoverage,
        confidence: MetricConfidence
    ) {
        self.usedPercent = usedPercent
        self.coveredProviders = coveredProviders
        self.coverage = coverage
        self.confidence = confidence
    }
}

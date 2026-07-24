import Foundation

/// The public, versioned quota snapshot Tokei exposes to orchestrating agents
/// (issue #57). It is deliberately **decoupled from the internal stores**: a stable
/// machine-readable contract that the `tokei` helper reads and that the
/// `AgentSnapshotWriter` produces after every refresh.
///
/// SECURITY INVARIANT: this schema carries **only** percentages, token counts, and
/// timestamps — never a token, cookie, bearer, or any credential. Both the writer
/// and any reviewer must keep it that way; it is a file other processes can read.
///
/// The same source file is compiled into the Core framework (so the writer can
/// produce it) and directly into the `tokei` CLI target (so it can decode it without
/// linking the whole app framework). It therefore depends on Foundation only.
public struct AgentSnapshot: Codable, Sendable, Equatable {
    /// Bump when a field changes shape in a non-additive way. Readers should tolerate
    /// unknown newer versions by reading what they understand.
    public static let currentSchemaVersion = 1

    /// Snapshots older than this (relative to the reader's clock) are reported as
    /// `stale`. Covers both "app not running" and "app running but hasn't refreshed
    /// recently" — both collapse to "`generatedAt` is old".
    public static let stalenessThreshold: TimeInterval = 600 // 10 minutes

    public let schemaVersion: Int
    /// When the app wrote this snapshot (UTC).
    public let generatedAt: Date
    public let providers: [AgentProvider]
    /// Cross-plan utilization 0…100 (peak-per-provider, averaged) — nil when no
    /// provider reported usable quota.
    public let aggregateUtilizationPercent: Double?
    public let recommendation: AgentRecommendation?

    /// Reader-computed, **omitted on disk** (the writer never sets them). The `tokei`
    /// helper populates these when emitting a response so agents never treat old data
    /// as live. See `withStaleness(asOf:)`.
    public var stale: Bool?
    public var ageSeconds: Int?

    public init(
        schemaVersion: Int = AgentSnapshot.currentSchemaVersion,
        generatedAt: Date,
        providers: [AgentProvider],
        aggregateUtilizationPercent: Double?,
        recommendation: AgentRecommendation?,
        stale: Bool? = nil,
        ageSeconds: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.providers = providers
        self.aggregateUtilizationPercent = aggregateUtilizationPercent
        self.recommendation = recommendation
        self.stale = stale
        self.ageSeconds = ageSeconds
    }
}

/// One provider's public usage — percentages, a token count, and timestamps only.
public struct AgentProvider: Codable, Sendable, Equatable {
    /// Stable machine id (`ProviderID.rawValue`, e.g. `"claude_code"`).
    public let id: String
    public let displayName: String
    public let windows: [AgentWindow]
    /// Total tokens attributed to today, when the provider can derive them.
    public let tokensToday: Int?
    /// When this provider last synced (UTC), if known.
    public let lastUpdated: Date?

    public init(
        id: String,
        displayName: String,
        windows: [AgentWindow],
        tokensToday: Int?,
        lastUpdated: Date?
    ) {
        self.id = id
        self.displayName = displayName
        self.windows = windows
        self.tokensToday = tokensToday
        self.lastUpdated = lastUpdated
    }
}

/// A single quota window as a percentage gauge.
public struct AgentWindow: Codable, Sendable, Equatable {
    /// `QuotaWindowType.rawValue` — `fiveHour | weekly | monthly | credits | perModel | …`.
    public let type: String
    /// Fraction of this window's ceiling consumed, 0…100.
    public let usedPercent: Double
    /// When the window's budget refills (UTC), if the provider reports it.
    public let resetsAt: Date?
    /// How trustworthy the number is: `official | local_estimate | unavailable`.
    /// Agents must not treat `local_estimate`/`unavailable` as hard limits.
    public let confidence: String
    /// Where the reading came from (diagnostic label, e.g. `"oauth_usage_api"`).
    public let source: String

    public init(
        type: String,
        usedPercent: Double,
        resetsAt: Date?,
        confidence: String,
        source: String
    ) {
        self.type = type
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.confidence = confidence
        self.source = source
    }
}

/// A routing hint for an orchestrator deciding which tool to delegate to. Reuses the
/// least-filled-provider idea behind the human-facing "Route work here" chip (#37).
public struct AgentRecommendation: Codable, Sendable, Equatable {
    /// Provider id to prefer (least-utilized), or nil when there isn't enough signal.
    public let routeTo: String?
    /// Provider ids to avoid (utilization at/over the avoid threshold).
    public let avoid: [String]
    /// Human-readable justification.
    public let reason: String

    public init(routeTo: String?, avoid: [String], reason: String) {
        self.routeTo = routeTo
        self.avoid = avoid
        self.reason = reason
    }
}

// MARK: - Location & coding (shared by writer and reader so they never drift)

public extension AgentSnapshot {
    static let defaultDirectoryName = "AIUsageDashboard"
    static let defaultFileName = "agent-snapshot.json"

    /// `~/Library/Application Support/AIUsageDashboard/agent-snapshot.json`.
    /// Same app-support idiom `UsageStore`/`QuotaSeriesStore` use, so the helper and
    /// the app agree on the path without sharing code across the target boundary.
    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent(defaultDirectoryName, isDirectory: true)
            .appendingPathComponent(defaultFileName, isDirectory: false)
    }

    /// Canonical encoder — ISO8601 dates, stable key order, pretty-printed. Matches
    /// the house style in `QuotaSeriesStore`/`CooldownStore`.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// Canonical decoder — must mirror `makeEncoder()`'s date strategy.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Staleness (reader-side; pure, clock-injected for testability)

public extension AgentSnapshot {
    /// Seconds between `generatedAt` and `now`, never negative (a clock skew that
    /// puts `generatedAt` in the future reads as age 0, not "fresh forever").
    func age(asOf now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(generatedAt))
    }

    func isStale(asOf now: Date, threshold: TimeInterval = AgentSnapshot.stalenessThreshold) -> Bool {
        age(asOf: now) > threshold
    }

    /// A copy with the reader-computed `stale`/`ageSeconds` fields populated. Callers
    /// emit this (not the raw on-disk value) so a stale snapshot is never served silently.
    func withStaleness(asOf now: Date, threshold: TimeInterval = AgentSnapshot.stalenessThreshold) -> AgentSnapshot {
        var copy = self
        copy.ageSeconds = Int(age(asOf: now).rounded())
        copy.stale = age(asOf: now) > threshold
        return copy
    }
}

// MARK: - Shared formatting (used by both AgentRecommendationEngine and StatusFormatting,
// which independently reimplemented this bucketing — kept here since this file is the one
// already compiled into both the Core framework and the `tokei` CLI target)

public extension AgentSnapshot {
    /// Compact "3h" / "12m" / "<1m" for a positive duration. Callers own how to handle a
    /// non-positive interval (omit the clause vs. show "now") since that's caller-specific.
    static func compactDuration(_ interval: TimeInterval) -> String {
        if interval >= 3600 { return "\(Int(interval / 3600))h" }
        if interval >= 60 { return "\(Int(interval / 60))m" }
        return "<1m"
    }
}

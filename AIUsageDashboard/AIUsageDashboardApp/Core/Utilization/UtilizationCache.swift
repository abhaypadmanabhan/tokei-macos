import Foundation

/// Robustness *primitives* for live utilization: a TTL cache that expires early at
/// the next quota reset, a persisted last-good read per provider, and a **global**
/// 429 cooldown marker. The intent: a surface consults `fresh`/`isCoolingDown`
/// before fetching, and on a shared-budget 429 every surface sharing this instance
/// serves stale instead of flashing red.
///
/// NOTE: this ships the primitives fully tested but **not yet wired** into the
/// fetch paths (`AntigravityQuotaClient` / `CursorUsageClient` still throw on 429).
/// Wiring the clients to `noteRateLimited`/`isCoolingDown` lands with the Claude
/// live-quota fetch (#5) that reuses this layer — this cycle changes no existing
/// behavior. Until then nothing calls these methods outside tests.
///
/// An `actor` with an **injected clock** — the shared mutable state (entries,
/// cooldown) is serialized by the actor, and time is a parameter so the
/// concurrency-visible behavior is unit-testable with no real network and no sleep.
///
/// SECURITY INVARIANT: this cache stores `Utilization` values — percentages, reset
/// times, and a plan label — and NOTHING else. No token, bearer, or csrf ever
/// enters it, so nothing sensitive is ever written to the sidecar file on disk.
public actor UtilizationCache {
    /// The process-wide instance. Sharing one instance is what makes the 429
    /// cooldown *global*: a 429 seen by any surface is observed by all of them.
    public static let shared = UtilizationCache()

    private struct Entry {
        let utilizations: [Utilization]
        /// When the cached reading stops being *fresh*. `distantPast` marks a value
        /// loaded from disk on launch — kept as last-good, never served as fresh.
        let expiresAt: Date
    }

    private let now: @Sendable () -> Date
    private let ttl: TimeInterval
    private let cooldown: TimeInterval
    private let directory: URL
    private let fileName: String

    private var entries: [ProviderID: Entry] = [:]
    private var cooldownUntil: Date?
    private var didLoad = false

    public init(
        now: @escaping @Sendable () -> Date = { Date() },
        ttl: TimeInterval = 300,
        cooldown: TimeInterval = 60,
        directory: URL? = nil,
        fileName: String = "utilization-cache.json"
    ) {
        self.now = now
        self.ttl = ttl
        self.cooldown = cooldown
        if let directory {
            self.directory = directory
        } else {
            let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            let appSupport = urls.first ?? FileManager.default.temporaryDirectory
            self.directory = appSupport.appendingPathComponent("AIUsageDashboard", isDirectory: true)
        }
        self.fileName = fileName
    }

    // MARK: - Reads

    /// The cached reading while it is still fresh, else `nil` — the signal to fetch.
    /// Freshness ends at `now + ttl`, or earlier at the window's next reset.
    public func fresh(for providerID: ProviderID) -> [Utilization]? {
        ensureLoaded()
        guard let entry = entries[providerID], now() < entry.expiresAt else { return nil }
        return entry.utilizations
    }

    /// The most recent stored reading regardless of freshness — what surfaces show
    /// while cooling down or when a fetch fails. Survives app relaunch via the sidecar.
    public func lastGood(for providerID: ProviderID) -> [Utilization]? {
        ensureLoaded()
        return entries[providerID]?.utilizations
    }

    // MARK: - Writes

    /// Record a fresh reading. Freshness expires at `now + ttl` or the earliest
    /// window reset, whichever comes first, and the value is persisted as last-good.
    public func store(_ utilizations: [Utilization], for providerID: ProviderID) {
        ensureLoaded()
        entries[providerID] = Entry(utilizations: utilizations, expiresAt: expiry(for: utilizations))
        persist()
    }

    private func expiry(for utilizations: [Utilization]) -> Date {
        let ttlExpiry = now().addingTimeInterval(ttl)
        guard let earliestReset = utilizations.compactMap(\.resetAt).min() else { return ttlExpiry }
        return min(ttlExpiry, earliestReset)
    }

    // MARK: - Global 429 cooldown

    /// Mark a shared-budget rate-limit. Every surface consulting this instance then
    /// serves stale instead of calling again until the cooldown elapses. Honors a
    /// server-provided `retryAfter`, falling back to the default cooldown.
    public func noteRateLimited(retryAfter: TimeInterval? = nil) {
        cooldownUntil = now().addingTimeInterval(retryAfter ?? cooldown)
    }

    /// True while a 429 cooldown is in effect — callers should serve `lastGood`.
    public func isCoolingDown() -> Bool {
        guard let cooldownUntil else { return false }
        return now() < cooldownUntil
    }

    /// Seconds until the cooldown lifts, or `nil` when not cooling down.
    public func cooldownRemaining() -> TimeInterval? {
        guard let cooldownUntil, now() < cooldownUntil else { return nil }
        return cooldownUntil.timeIntervalSince(now())
    }

    // MARK: - Persistence (sidecar, additive — no UsageStore schema change)

    private var fileURL: URL { directory.appendingPathComponent(fileName) }

    private func ensureLoaded() {
        guard !didLoad else { return }
        didLoad = true
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([ProviderID: [Utilization]].self, from: data) else {
            return
        }
        // Loaded values are last-good only: mark them already-expired so `fresh`
        // never serves a reading carried across a relaunch.
        for (providerID, utilizations) in stored {
            entries[providerID] = Entry(utilizations: utilizations, expiresAt: .distantPast)
        }
    }

    private func persist() {
        let lastGood = entries.mapValues(\.utilizations)
        guard let data = try? JSONEncoder().encode(lastGood) else { return }

        // `.atomic` writes to a sibling temp file and renames in place, so a crash
        // mid-write leaves the previous good file intact — no manual temp dance needed.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

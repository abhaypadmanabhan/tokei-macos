import Foundation
import os

/// Writes the public `agent-snapshot.json` after every refresh cycle (issue #57).
///
/// It maps the snapshots Tokei already collects into the versioned public schema
/// (`AgentSnapshot`) and writes it atomically to
/// `~/Library/Application Support/AIUsageDashboard/agent-snapshot.json`. The mapping
/// (`buildSnapshot`) is pure and static so it can be unit-tested without touching disk.
///
/// SECURITY: only percentages, token counts, and timestamps leave here — see the
/// invariant on `AgentSnapshot`. No raw provider responses, tokens, or credentials.
public actor AgentSnapshotWriter {
    public static let shared = AgentSnapshotWriter()

    private static let log = Logger(subsystem: "ai.padzy.tokei", category: "AgentSnapshotWriter")

    private let directory: URL
    private let fileURL: URL
    private let encoder = AgentSnapshot.makeEncoder()

    /// - Parameter directory: overrides the app-support location (tests inject a temp dir).
    public init(directory: URL? = nil, fileName: String = AgentSnapshot.defaultFileName) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent(
                AgentSnapshot.defaultDirectoryName, isDirectory: true
            )
        }
        self.fileURL = self.directory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Where this writer persists — exposed for tests and diagnostics.
    public var location: URL { fileURL }

    /// Build the public snapshot from the latest provider snapshots and write it
    /// atomically. Returns whether the write succeeded; a failure is logged, never
    /// thrown, so it can't take down a refresh cycle.
    @discardableResult
    public func write(from snapshots: [ProviderSnapshot], generatedAt: Date = Date()) -> Bool {
        persist(Self.buildSnapshot(from: snapshots, generatedAt: generatedAt))
    }

    // MARK: - Pure mapping (internal stores → public schema)

    /// Map `[ProviderSnapshot]` to the public `AgentSnapshot`. Pure — no I/O, no clock
    /// beyond the injected `generatedAt` — so schema encoding is directly testable.
    public static func buildSnapshot(from snapshots: [ProviderSnapshot], generatedAt: Date) -> AgentSnapshot {
        let providers = snapshots.map(agentProvider(from:))
        let aggregate = UtilizationEngine.aggregate(from: snapshots)?.usedPercent
        let utilizations = UtilizationEngine.utilizations(from: snapshots)
        let displayNames = Dictionary(
            snapshots.map { ($0.providerID, $0.displayName) },
            uniquingKeysWith: { first, _ in first }
        )
        // Per-provider account breakdown, so the recommendation's `reason` can name the
        // account its headline number came from (multi-account Claude) rather than
        // leaving the reader to guess which `CLAUDE_CONFIG_DIR` the % belongs to.
        let accounts = Dictionary(
            snapshots.compactMap { snapshot -> (ProviderID, [AgentAccount])? in
                guard let accounts = snapshot.accounts else { return nil }
                return (snapshot.providerID, accounts.map(agentAccount(from:)))
            },
            uniquingKeysWith: { first, _ in first }
        )
        let recommendation = AgentRecommendationEngine.recommend(
            from: utilizations,
            displayNames: displayNames,
            accounts: accounts,
            now: generatedAt
        )
        return AgentSnapshot(
            generatedAt: generatedAt,
            providers: providers,
            aggregateUtilizationPercent: aggregate,
            recommendation: recommendation
        )
    }

    private static func agentProvider(from snapshot: ProviderSnapshot) -> AgentProvider {
        AgentProvider(
            id: snapshot.providerID.rawValue,
            displayName: snapshot.displayName,
            windows: snapshot.quotaWindows.compactMap(agentWindow(from:)),
            tokensToday: snapshot.todayUsage.totalTokens,
            lastUpdated: snapshot.lastSyncedAt,
            // Absent rather than empty for single-account providers, so nothing changes
            // for readers that never had this field.
            accounts: snapshot.accounts.map { $0.map(agentAccount(from:)) }
        )
    }

    private static func agentAccount(from account: ProviderAccountUsage) -> AgentAccount {
        AgentAccount(
            id: account.id,
            label: account.label,
            windows: account.quotaWindows.compactMap(agentWindow(from:)),
            tokensToday: account.todayUsage.totalTokens
        )
    }

    /// A window becomes public only when it has a computable percentage — the same
    /// rule the utilization spine uses (`UtilizationEngine.usedPercent`), replicated
    /// here to keep `source` (which the spine drops) and avoid widening its API.
    private static func agentWindow(from window: QuotaWindow) -> AgentWindow? {
        guard let percent = UtilizationEngine.usedPercent(from: window) else { return nil }
        return AgentWindow(
            type: window.type.rawValue,
            usedPercent: percent,
            resetsAt: window.resetAt,
            confidence: publicConfidence(window.confidence),
            source: window.source,
            observedAt: window.observedAt
        )
    }

    /// Collapse the internal five-level confidence to the three public labels agents
    /// reason about: `official | local_estimate | unavailable`.
    private static func publicConfidence(_ confidence: MetricConfidence) -> String {
        switch confidence {
        case .exact, .providerReported: return "official"
        case .localParsed, .estimated: return "local_estimate"
        case .unavailable: return "unavailable"
        }
    }

    // MARK: - Atomic persistence

    private func persist(_ snapshot: AgentSnapshot) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(snapshot)
            // `.atomic` writes to a sibling temp file and renames — a reader never sees
            // a torn file, and a crash mid-write leaves the previous snapshot intact.
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            Self.log.error("agent snapshot write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

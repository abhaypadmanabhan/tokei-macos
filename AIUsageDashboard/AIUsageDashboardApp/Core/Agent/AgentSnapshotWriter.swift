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
        let headlineDecisions = Dictionary(
            uniqueKeysWithValues: snapshots.compactMap { snapshot -> (ProviderID, AccountQuotaDecision)? in
                guard let accounts = snapshot.accounts,
                      let decision = AccountQuotaDecision.headline(
                        among: accounts,
                        providerID: snapshot.providerID,
                        now: generatedAt
                      ) else { return nil }
                return (snapshot.providerID, decision)
            }
        )
        let providers = snapshots.map {
            agentProvider(
                from: $0,
                generatedAt: generatedAt,
                headlineDecision: headlineDecisions[$0.providerID]
            )
        }
        let aggregate = UtilizationEngine.aggregate(from: snapshots)?.usedPercent
        let utilizations = snapshots.flatMap { snapshot -> [Utilization] in
            let windows = headlineDecisions[snapshot.providerID]?.account.quotaWindows
                ?? snapshot.quotaWindows
            return windows.compactMap { window in
                guard let usedPercent = UtilizationEngine.usedPercent(from: window) else { return nil }
                return Utilization(
                    providerID: snapshot.providerID,
                    window: window.type,
                    usedPercent: usedPercent,
                    resetAt: window.resetAt,
                    confidence: window.confidence,
                    observedAt: window.observedAt
                )
            }
        }
        let displayNames = Dictionary(
            snapshots.map { ($0.providerID, $0.displayName) },
            uniquingKeysWith: { first, _ in first }
        )
        let recommendation = AgentRecommendationEngine.recommend(
            from: utilizations,
            displayNames: displayNames,
            providers: providers,
            now: generatedAt
        )
        return AgentSnapshot(
            generatedAt: generatedAt,
            providers: providers,
            aggregateUtilizationPercent: aggregate,
            recommendation: recommendation
        )
    }

    private static func agentProvider(
        from snapshot: ProviderSnapshot,
        generatedAt: Date,
        headlineDecision: AccountQuotaDecision?
    ) -> AgentProvider {
        let headlineAccountID = headlineDecision.map {
            AccountQuotaDecision.stableID(for: $0.account, providerID: snapshot.providerID)
        }
        return AgentProvider(
            id: snapshot.providerID.rawValue,
            displayName: snapshot.displayName,
            windows: (headlineDecision?.account.quotaWindows ?? snapshot.quotaWindows)
                .compactMap(agentWindow(from:)),
            tokensToday: snapshot.todayUsage.totalTokens,
            lastUpdated: snapshot.lastSyncedAt,
            // Absent rather than empty for single-account providers, so nothing changes
            // for readers that never had this field.
            accounts: snapshot.accounts.map { accounts in
                accounts.map {
                    agentAccount(from: $0, providerID: snapshot.providerID, generatedAt: generatedAt)
                }
            },
            headlineAccountID: headlineAccountID
        )
    }

    private static func agentAccount(
        from account: ProviderAccountUsage,
        providerID: ProviderID,
        generatedAt: Date
    ) -> AgentAccount {
        let decision = AccountQuotaDecision.evaluate(
            account,
            providerID: providerID,
            now: generatedAt
        )
        return AgentAccount(
            id: account.id,
            label: account.label,
            windows: account.quotaWindows.compactMap(agentWindow(from:)),
            tokensToday: account.todayUsage.totalTokens,
            accountID: AccountQuotaDecision.stableID(for: account, providerID: providerID),
            selector: account.selector,
            quota: AgentAccountQuota(
                status: decision.status.rawValue,
                usedPercent: decision.usedPercent,
                headroomPercent: decision.headroomPercent,
                bindingWindowIndex: decision.bindingWindowIndex,
                validUntil: decision.validUntil,
                reasonCode: quotaReasonCode(for: decision, account: account)
            )
        )
    }

    private static func quotaReasonCode(
        for decision: AccountQuotaDecision,
        account: ProviderAccountUsage
    ) -> String? {
        guard decision.status == .unknown else { return nil }
        return account.quotaWindows.compactMap(UtilizationEngine.usedPercent(from:)).isEmpty
            ? "no_quota_reading"
            : "untrusted_reading"
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
            observedAt: window.observedAt,
            label: window.label,
            bucketKey: window.bucketKey
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

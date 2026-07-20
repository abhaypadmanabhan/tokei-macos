import XCTest
@testable import AIUsageDashboardCore

/// Unit tests for the provider-chip stat resolution and the shared "today across
/// providers" merge in `MaxxerMath` (compiled into this bundle from
/// `UI/MenuBar/MaxxerMath.swift` — see project.yml).
///
/// The chip strip replaced the sidebar's provider rows in the WP-4 IA
/// consolidation, and a chip has room for exactly ONE number. Which number that
/// is, is the whole decision — these tests pin the precedence so a provider can
/// never end up showing a confident `0` in place of a live quota reading, or a
/// `—` when it had something honest to say.
final class MaxxerChipStatTests: XCTestCase {

    // MARK: - Fixtures

    private func snapshot(
        _ id: ProviderID,
        today: TokenUsage = .unavailable,
        plan: String? = nil
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: id,
            displayName: id.rawValue,
            authStatus: .authenticated,
            todayUsage: today,
            weekUsage: .unavailable,
            warnings: plan.map { [ProviderWarning(message: "Plan: \($0)", level: .info)] } ?? []
        )
    }

    private func utilization(_ id: ProviderID, percent: Double) -> Utilization {
        Utilization(
            providerID: id,
            window: .weekly,
            usedPercent: percent,
            resetAt: Date(timeIntervalSince1970: 1_800_000_000),
            plan: nil,
            confidence: .providerReported
        )
    }

    private func stat(
        _ id: ProviderID = .claudeCode,
        snapshot: ProviderSnapshot?,
        utilizations: [Utilization] = [],
        planLabel: String? = nil,
        isLoading: Bool = false
    ) -> MaxxerMath.ChipStat {
        MaxxerMath.chipStat(
            providerID: id,
            snapshot: snapshot,
            utilizations: utilizations,
            planLabel: planLabel,
            isLoading: isLoading
        )
    }

    // MARK: - Precedence

    func testTodayTokensWinWhenTheProviderReportsAny() {
        let result = stat(
            snapshot: snapshot(.claudeCode,
                               today: TokenUsage(inputTokens: 900, outputTokens: 100, confidence: .exact)),
            utilizations: [utilization(.claudeCode, percent: 94)]
        )
        XCTAssertEqual(result, .tokens(1_000))
    }

    func testFallsBackToTightestWindowWhenNoTokensAreReported() {
        let result = stat(
            .cursor,
            snapshot: snapshot(.cursor),
            utilizations: [utilization(.cursor, percent: 78)]
        )
        XCTAssertEqual(result, .utilization(78))
    }

    func testPicksTheTightestWindowNotTheFirst() {
        let result = stat(
            .cursor,
            snapshot: snapshot(.cursor),
            utilizations: [utilization(.cursor, percent: 12), utilization(.cursor, percent: 91)]
        )
        XCTAssertEqual(result, .utilization(91))
    }

    func testIgnoresOtherProvidersWindows() {
        let result = stat(
            .cursor,
            snapshot: snapshot(.cursor),
            utilizations: [utilization(.claudeCode, percent: 94)],
            planLabel: "Pro"
        )
        // Claude's 94% must never leak onto Cursor's chip.
        XCTAssertEqual(result, .plan("Pro"))
    }

    func testFallsBackToPlanLabelWhenThereIsNeitherNumber() {
        XCTAssertEqual(stat(snapshot: snapshot(.antigravity), planLabel: "Pro"), .plan("Pro"))
    }

    func testEmptyPlanLabelIsNotShownAsAPlan() {
        XCTAssertEqual(stat(snapshot: snapshot(.antigravity), planLabel: ""), .none)
    }

    // MARK: - Zero is a reading, not a placeholder

    func testGenuineZeroTokensRenderAsZeroWhenNothingElseExists() {
        let result = stat(
            snapshot: snapshot(.claudeCode, today: TokenUsage(inputTokens: 0, outputTokens: 0, confidence: .exact)),
            planLabel: "Max"
        )
        // A real "0 today" outranks the plan label — it is a measurement.
        XCTAssertEqual(result, .tokens(0))
    }

    func testLiveWindowOutranksAGenuineZero() {
        let result = stat(
            snapshot: snapshot(.claudeCode, today: TokenUsage(inputTokens: 0, outputTokens: 0, confidence: .exact)),
            utilizations: [utilization(.claudeCode, percent: 94)]
        )
        // "0 today" next to a 94%-full week is the less useful of the two reads.
        XCTAssertEqual(result, .utilization(94))
    }

    // MARK: - Loading / nothing

    func testNoSnapshotWhileSyncingReadsAsSyncing() {
        XCTAssertEqual(stat(snapshot: nil, isLoading: true), .syncing)
    }

    func testNoSnapshotAndNotSyncingReadsAsNothing() {
        XCTAssertEqual(stat(snapshot: nil, isLoading: false), .none)
    }

    func testSnapshotWithNothingToSayIsNotSyncingEvenMidSync() {
        // A provider that HAS synced but reports nothing must not pretend to still
        // be loading — that would make an honest empty look like a pending fetch.
        XCTAssertEqual(stat(snapshot: snapshot(.cline), isLoading: true), .none)
    }

    // MARK: - Merged today

    func testMergedTodayUsageSumsAcrossProviders() {
        let merged = MaxxerMath.mergedTodayUsage(in: [
            snapshot(.claudeCode, today: TokenUsage(inputTokens: 100, outputTokens: 10, confidence: .exact)),
            snapshot(.codex, today: TokenUsage(inputTokens: 200, outputTokens: 20, confidence: .exact)),
        ])
        XCTAssertEqual(merged.totalTokens, 330)
    }

    func testMergedTodayUsageDegradesConfidenceToTheWeakestContributor() {
        let merged = MaxxerMath.mergedTodayUsage(in: [
            snapshot(.claudeCode, today: TokenUsage(inputTokens: 100, outputTokens: 0, confidence: .exact)),
            snapshot(.codex, today: TokenUsage(inputTokens: 100, outputTokens: 0, confidence: .localParsed)),
        ])
        XCTAssertEqual(merged.confidence, .localParsed)
    }

    func testMergedTodayUsageKeepsAGoodConfidenceWhenEveryContributorIsGood() {
        // Regression: the merge used to be seeded with `.unavailable`, which pinned
        // every result to `.unavailable` and made the hero's badge meaningless.
        let merged = MaxxerMath.mergedTodayUsage(in: [
            snapshot(.claudeCode, today: TokenUsage(inputTokens: 100, outputTokens: 0, confidence: .exact)),
            snapshot(.codex, today: TokenUsage(inputTokens: 100, outputTokens: 0, confidence: .exact)),
        ])
        XCTAssertEqual(merged.confidence, .exact)
        XCTAssertEqual(merged.totalTokens, 200)
    }

    func testMergedTodayUsageIgnoresProvidersThatMeasuredNothing() {
        // Regression: an agent with no token signal used to drag the merged
        // confidence to `.unavailable`, so a day of exact Claude tokens rendered
        // with an UNAVAILABLE badge on the hero.
        let merged = MaxxerMath.mergedTodayUsage(in: [
            snapshot(.claudeCode, today: TokenUsage(inputTokens: 500, outputTokens: 0, confidence: .exact)),
            snapshot(.cursor, today: .unavailable),
        ])
        XCTAssertEqual(merged.confidence, .exact)
        XCTAssertEqual(merged.totalTokens, 500)
    }

    func testMergedTodayUsageOfNothingIsUnavailableNotZero() {
        // The tab pill renders "—" off this: an empty canvas must not claim a
        // measured zero for the day.
        XCTAssertNil(MaxxerMath.mergedTodayUsage(in: []).totalTokens)
    }
}

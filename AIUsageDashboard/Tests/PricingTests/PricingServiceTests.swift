import XCTest
@testable import AIUsageDashboardCore

final class PricingServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // A fixed instant so freshness checks never depend on the wall clock / time zone.
    private static let fixedNow = Date(timeIntervalSince1970: 1_760_000_000) // 2025-10-09T...Z
    private func clock(_ date: Date = fixedNow) -> @Sendable () -> Date { { date } }

    private func cacheURL() -> URL {
        tempDirectory.appendingPathComponent("litellm-model-prices.json")
    }

    private func writeCache(_ rows: [String: LiteLLMRate], mtime: Date, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(rows)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
    }

    private func tokens(
        input: Int = 1_000_000,
        output: Int = 1_000_000,
        cacheRead: Int = 1_000_000,
        cacheCreation: Int = 0,
        reasoning: Int = 0
    ) -> TokenUsage {
        TokenUsage(
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheCreationTokens: cacheCreation,
            reasoningTokens: reasoning,
            confidence: .localParsed
        )
    }

    // MARK: - Test doubles

    /// Returns a table containing a `refresh-sentinel` row so a test can detect
    /// whether a live fetch actually happened, without counting calls.
    private struct SentinelRefresher: PricingTableRefreshing {
        func refresh(current table: PricingTable) async throws -> PricingTable {
            var rates = table.rates
            rates["refresh-sentinel"] = PricingRate(inputPerMillion: 1.0, cachedInputPerMillion: 1.0, outputPerMillion: 1.0)
            return PricingTable(rates: rates)
        }
    }

    /// Simulates a failed network refresh.
    private struct ThrowingRefresher: PricingTableRefreshing {
        func refresh(current table: PricingTable) async throws -> PricingTable {
            throw PricingServiceError.badResponse
        }
    }

    private func seedTable() -> PricingTable {
        PricingTable(rates: [
            "gpt-5": PricingRate(inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.00)
        ])
    }

    // MARK: - LiteLLM parse + curated overrides

    func testRefresherParsesLiveTableAndCuratedOverridesWin() async throws {
        let refresher = LiteLLMPricingTableRefresher(fetcher: { PricingFixtures.liteLLMTableData })
        let curated = seedTable() // curated gpt-5 = 1.25/M

        let merged = try await refresher.refresh(current: curated)

        // Live-only models come through.
        XCTAssertNotNil(merged.resolveRate(for: "deepseek-chat"))
        XCTAssertNotNil(merged.resolveRate(for: "mistral-large-latest"))
        // Curated seed overrides the live value (1.25/M, not the fixture's 9.99/M).
        XCTAssertEqual(merged.resolveRate(for: "gpt-5")?.inputPerMillion, 1.25)
        // The documentation stub and metadata-only rows are dropped.
        XCTAssertNil(merged.resolveRate(for: "sample_spec"))
        XCTAssertNil(merged.resolveRate(for: "embed-meta-only"))
    }

    func testParseLiteLLMSlimsToFourFieldsAndSkipsNonPriced() {
        let rates = PricingService.parseLiteLLM(PricingFixtures.liteLLMTableData)

        // deepseek-chat converts per-token → per-million; absent cache-creation
        // defaults to the input rate.
        guard let deepseek = rates["deepseek-chat"] else {
            return XCTFail("deepseek-chat should be priced")
        }
        XCTAssertEqual(deepseek.inputPerMillion, 0.27, accuracy: 0.000_001)
        XCTAssertEqual(deepseek.outputPerMillion, 1.10, accuracy: 0.000_001)
        XCTAssertEqual(deepseek.cachedInputPerMillion, 0.07, accuracy: 0.000_001)
        XCTAssertEqual(deepseek.cacheCreationInputPerMillion, 0.27, accuracy: 0.000_001)

        // Row with input but zero output is still usable.
        XCTAssertNotNil(rates["text-embedding-3-small"])
        // Stub + metadata-only rows are excluded.
        XCTAssertNil(rates["sample_spec"])
        XCTAssertNil(rates["embed-meta-only"])
    }

    func testUnparseableLiveTableThrowsSoCallerKeepsCurrent() async {
        let refresher = LiteLLMPricingTableRefresher(fetcher: { PricingFixtures.notATableData })
        do {
            _ = try await refresher.refresh(current: seedTable())
            XCTFail("expected an error for an unparseable table")
        } catch {
            XCTAssertEqual(error as? PricingServiceError, .emptyTable)
        }
    }

    // MARK: - Fallback chain

    func testFreshCacheServesDiskWithoutFetching() async {
        let url = cacheURL()
        try? writeCache(
            ["deepseek-chat": LiteLLMRate(
                inputCostPerToken: 0.00000027,
                outputCostPerToken: 0.0000011,
                cacheReadInputTokenCost: 0.00000007,
                cacheCreationInputTokenCost: nil
            )],
            mtime: Self.fixedNow.addingTimeInterval(-3_600), // 1h old → fresh
            to: url
        )

        let service = PricingService(
            refresher: SentinelRefresher(),
            now: clock(),
            cacheURL: url,
            seed: PricingTable(rates: [:])
        )
        await service.refreshIfStale()

        // Disk cache resolves; the refresher was never consulted (no sentinel).
        let disk = await service.cost(model: "deepseek-chat", tokens: tokens())
        let sentinel = await service.cost(model: "refresh-sentinel", tokens: tokens())
        XCTAssertNotNil(disk)
        XCTAssertNil(sentinel)
    }

    func testStaleCacheFetchFailureServesStaleDisk() async {
        let url = cacheURL()
        try? writeCache(
            ["deepseek-chat": LiteLLMRate(
                inputCostPerToken: 0.00000027,
                outputCostPerToken: 0.0000011,
                cacheReadInputTokenCost: 0.00000007,
                cacheCreationInputTokenCost: nil
            )],
            mtime: Self.fixedNow.addingTimeInterval(-25 * 3_600), // 25h old → stale
            to: url
        )

        let service = PricingService(
            refresher: ThrowingRefresher(),
            now: clock(),
            cacheURL: url,
            seed: PricingTable(rates: [:])
        )
        await service.refreshIfStale() // stale → fetch attempted → fails → keep disk

        let disk = await service.cost(model: "deepseek-chat", tokens: tokens())
        XCTAssertNotNil(disk)
    }

    func testNoCacheFetchFailureFallsBackToSeed() async {
        let service = PricingService(
            refresher: ThrowingRefresher(),
            now: clock(),
            cacheURL: cacheURL(), // no file written
            seed: seedTable()
        )
        await service.refreshIfStale() // no cache, fetch fails → seed

        let known = await service.cost(model: "gpt-5", tokens: tokens())
        let unknown = await service.cost(model: "totally-unknown-model", tokens: tokens())
        XCTAssertNotNil(known)
        XCTAssertNil(unknown)
    }

    func testSuccessfulRefreshUpdatesTableAndWritesSlimCache() async throws {
        let url = cacheURL()
        let service = PricingService(
            refresher: LiteLLMPricingTableRefresher(fetcher: { PricingFixtures.liteLLMTableData }),
            now: clock(),
            cacheURL: url,
            seed: seedTable()
        )

        await service.refreshIfStale()

        // Live-only model now resolves; curated gpt-5 kept its override.
        let deepseek = await service.cost(model: "deepseek-chat", tokens: tokens())
        XCTAssertNotNil(deepseek)
        let gpt5 = await service.cost(model: "gpt-5", tokens: tokens(input: 1_000_000, output: 0, cacheRead: 0))
        XCTAssertEqual(try XCTUnwrap(gpt5), 1.25, accuracy: 0.000_001) // curated 1.25/M, not fixture 9.99

        // Cache written and slimmed to only the four snake_case cost fields.
        let data = try Data(contentsOf: url)
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
        let deepseekRow = try XCTUnwrap(raw?["deepseek-chat"])
        let allowed: Set<String> = [
            "input_cost_per_token", "output_cost_per_token",
            "cache_read_input_token_cost", "cache_creation_input_token_cost"
        ]
        XCTAssertTrue(Set(deepseekRow.keys).isSubset(of: allowed), "cache row not slimmed: \(deepseekRow.keys)")
        XCTAssertNil(deepseekRow["litellm_provider"])
        XCTAssertNil(deepseekRow["mode"])
    }

    func testUnknownModelReturnsNilAndIsNegativeCached() async {
        let service = PricingService(
            refresher: ThrowingRefresher(),
            now: clock(),
            cacheURL: cacheURL(),
            seed: seedTable()
        )

        let first = await service.cost(model: "mystery-xyz", tokens: tokens())
        let second = await service.cost(model: "mystery-xyz", tokens: tokens()) // cached negative, no crash
        let known = await service.cost(model: "gpt-5", tokens: tokens()) // known still resolves
        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertNotNil(known)
    }

    // MARK: - Clock-injected cache freshness boundary

    func testCacheFreshnessBoundaryUsesInjectedClock() async {
        // Exactly 24h old → stale (age < maxAge is false) → fetch happens (sentinel appears).
        let staleURL = tempDirectory.appendingPathComponent("stale.json")
        try? writeCache(
            ["gpt-5": LiteLLMRate(inputCostPerToken: 0.00000125, outputCostPerToken: 0.00001, cacheReadInputTokenCost: nil, cacheCreationInputTokenCost: nil)],
            mtime: Self.fixedNow.addingTimeInterval(-24 * 3_600),
            to: staleURL
        )
        let staleService = PricingService(refresher: SentinelRefresher(), now: clock(), cacheURL: staleURL, seed: PricingTable(rates: [:]))
        await staleService.refreshIfStale()
        let staleSentinel = await staleService.cost(model: "refresh-sentinel", tokens: tokens())
        XCTAssertNotNil(staleSentinel, "boundary age should be treated as stale")

        // One second under 24h → fresh → no fetch (no sentinel).
        let freshURL = tempDirectory.appendingPathComponent("fresh.json")
        try? writeCache(
            ["gpt-5": LiteLLMRate(inputCostPerToken: 0.00000125, outputCostPerToken: 0.00001, cacheReadInputTokenCost: nil, cacheCreationInputTokenCost: nil)],
            mtime: Self.fixedNow.addingTimeInterval(-(24 * 3_600 - 1)),
            to: freshURL
        )
        let freshService = PricingService(refresher: SentinelRefresher(), now: clock(), cacheURL: freshURL, seed: PricingTable(rates: [:]))
        await freshService.refreshIfStale()
        let freshSentinel = await freshService.cost(model: "refresh-sentinel", tokens: tokens())
        XCTAssertNil(freshSentinel, "under-24h cache should be fresh")
    }

    // MARK: - No-regression parity with the legacy static Codex table

    func testCodexSeedParityWithLegacyStaticTable() async {
        // Service on the real bundled seed, no live table involved.
        let service = PricingService(
            refresher: ThrowingRefresher(),
            now: clock(),
            cacheURL: cacheURL(),
            seed: PricingSeed.defaultTable
        )
        let codexTokens = TokenUsage(
            inputTokens: 1_000_000,
            outputTokens: 500_000,
            cacheReadTokens: 200_000,
            cacheCreationTokens: 0, // Codex never emits cache-creation tokens
            reasoningTokens: 100_000,
            confidence: .localParsed
        )

        let viaService = await service.cost(model: "gpt-4.1", tokens: codexTokens)
        let viaLegacy = CodexPricing.estimateCost(tokens: codexTokens, model: "gpt-4.1")
        XCTAssertNotNil(viaService)
        XCTAssertNotNil(viaLegacy)
        XCTAssertEqual(try XCTUnwrap(viaService), try XCTUnwrap(viaLegacy), accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(viaService), 6.90, accuracy: 0.000_001)

        // Newer minor still prices under the base family; a truly-unknown family is nil.
        let newerMinor = await service.cost(model: "gpt-5.5", tokens: codexTokens)
        let unknownFamily = await service.cost(model: "gpt-6-ultra", tokens: codexTokens)
        XCTAssertNotNil(newerMinor)
        XCTAssertNil(unknownFamily)
    }
}

import Foundation

/// Resilient, self-updating model-price resolver.
///
/// Replaces the frozen static snapshot with a live feed while keeping the app fully
/// functional offline. Prices come from LiteLLM's public
/// `model_prices_and_context_window.json`, slimmed to the four per-token cost fields
/// this app charges against, and layered under the bundled curated seed
/// (`PricingSeed.defaultTable`).
///
/// Availability chain, in order (the first that yields data wins):
///   1. Fresh (< 24h) on-disk cache — no network.
///   2. Live fetch of the LiteLLM table — async, ~15s timeout, off the UI path.
///   3. Stale on-disk cache — when the fetch fails.
///   4. Bundled seed (`PricingSeed.defaultTable`) — when no cache exists at all.
///
/// Per-model lookup order: **curated overrides → LiteLLM table → negative cache**.
/// Curated seed rows always override the live table (so verified numbers never
/// regress), the live table extends coverage to hundreds of other models, and an
/// unrecognised model resolves to `nil` once and is remembered so repeated lookups
/// never re-scan the table.
///
/// This is deliberately built on the existing `Core/Pricing` abstractions
/// (`PricingTable`, `PricingRate`, `PricingEngine`, `PricingSeed`) and the
/// pre-existing `PricingTableRefreshing` seam rather than a parallel price model, so
/// there is a single pricing engine and a single curated seed in the codebase.
public actor PricingService {
    private let refresher: any PricingTableRefreshing
    private let now: @Sendable () -> Date
    private let cacheURL: URL
    private let seed: PricingTable
    private let maxCacheAge: TimeInterval

    private var engine: PricingEngine?
    private var negativeCache: Set<String> = []
    private var isRefreshing = false

    public init(
        refresher: any PricingTableRefreshing,
        now: @escaping @Sendable () -> Date = { Date() },
        cacheURL: URL,
        seed: PricingTable = PricingSeed.defaultTable,
        maxCacheAge: TimeInterval = PricingService.defaultMaxCacheAge
    ) {
        self.refresher = refresher
        self.now = now
        self.cacheURL = cacheURL
        self.seed = seed
        self.maxCacheAge = maxCacheAge
    }

    // MARK: - Lookup

    /// API-equivalent USD cost of `tokens` under `model`, or `nil` when no public
    /// rate resolves. Never performs network I/O: it resolves against the currently
    /// loaded table (fresh/stale cache, else the bundled seed), lazily loading it on
    /// first use. Unknown models are remembered so repeated lookups are O(1).
    public func cost(model: String, tokens: TokenUsage) -> Double? {
        loadIfNeeded()
        let key = model.lowercased()
        if negativeCache.contains(key) { return nil }
        guard let amount = engine?.cost(model: model, tokens: tokens) else {
            negativeCache.insert(key)
            return nil
        }
        return amount
    }

    // MARK: - Refresh

    /// Refreshes the in-memory table honoring the 24h cache: a fresh disk cache short
    /// -circuits the network; otherwise it fetches the live table (via the injected
    /// refresher), rewrites the slim cache, and swaps the table in. Never throws and
    /// never blocks a caller's UI — on any failure it keeps serving the best data it
    /// already has (stale cache, else seed). Safe to call repeatedly and concurrently.
    public func refreshIfStale() async {
        loadIfNeeded()
        if isCacheFresh() { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let updated = try await refresher.refresh(current: seed)
            writeCache(Self.slim(updated))
            setTable(updated)
            negativeCache.removeAll()
        } catch {
            // Keep whatever `loadIfNeeded` already installed (stale cache or seed).
        }
    }

    // MARK: - Table loading

    private func loadIfNeeded() {
        guard engine == nil else { return }
        if let cached = readCache() {
            setTable(mergeSeedOver(cached))
        } else {
            setTable(seed)
        }
    }

    private func setTable(_ table: PricingTable) {
        engine = PricingEngine(table: table)
    }

    /// Curated seed rows always win over the live/cached table.
    private func mergeSeedOver(_ liteLLM: [String: PricingRate]) -> PricingTable {
        var rates = liteLLM
        for (slug, rate) in seed.rates { rates[slug] = rate }
        return PricingTable(rates: rates)
    }

    // MARK: - Disk cache (mtime-based, 24h)

    private func isCacheFresh() -> Bool {
        guard let mtime = cacheModificationDate() else { return false }
        let age = now().timeIntervalSince(mtime)
        return age >= 0 && age < maxCacheAge
    }

    private func cacheModificationDate() -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path) else {
            return nil
        }
        return attrs[.modificationDate] as? Date
    }

    private func readCache() -> [String: PricingRate]? {
        guard let data = try? Data(contentsOf: cacheURL),
              let slim = try? JSONDecoder().decode([String: LiteLLMRate].self, from: data) else {
            return nil
        }
        let rates = slim.compactMapValues { $0.pricingRate }
        return rates.isEmpty ? nil : rates
    }

    private func writeCache(_ slim: [String: LiteLLMRate]) {
        guard let data = try? JSONEncoder().encode(slim) else { return }
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // A non-writable cache dir is non-fatal: the in-memory table still serves.
        }
    }

    // MARK: - LiteLLM parsing

    /// Decodes the raw LiteLLM table, slimming every usable row to a `PricingRate`.
    /// Rows are skipped when they carry no input price (e.g. the `sample_spec`
    /// documentation stub or metadata-only entries). Tolerant of the file's many
    /// non-cost fields and of individual malformed cost fields.
    static func parseLiteLLM(_ data: Data) -> [String: PricingRate] {
        guard let raw = try? JSONDecoder().decode([String: LiteLLMRate].self, from: data) else {
            return [:]
        }
        var out: [String: PricingRate] = [:]
        out.reserveCapacity(raw.count)
        for (key, row) in raw {
            guard key != "sample_spec", let rate = row.pricingRate else { continue }
            out[key.lowercased()] = rate
        }
        return out
    }

    /// Serialises a resolved table back to the slim 4-field per-token shape for disk.
    static func slim(_ table: PricingTable) -> [String: LiteLLMRate] {
        table.rates.mapValues { LiteLLMRate(perMillion: $0) }
    }

    // MARK: - Defaults / shared instance

    public static let defaultMaxCacheAge: TimeInterval = 24 * 60 * 60
    public static let defaultTimeout: TimeInterval = 15

    public static let liteLLMURL = URL(
        string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
    )!

    static func defaultCacheURL() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("AIUsageDashboard", isDirectory: true)
            .appendingPathComponent("litellm-model-prices.json")
    }

    /// Builds the production network fetcher: one GET with a bounded timeout, 200-only.
    public static func liveFetcher(
        url: URL = PricingService.liteLLMURL,
        timeout: TimeInterval = PricingService.defaultTimeout
    ) -> @Sendable () async throws -> Data {
        { @Sendable in
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw PricingServiceError.badResponse
            }
            return data
        }
    }

    /// App-wide instance: live LiteLLM feed, per-user caches dir, bundled seed.
    public static let shared = PricingService(
        refresher: LiteLLMPricingTableRefresher(),
        cacheURL: PricingService.defaultCacheURL(),
        seed: PricingSeed.defaultTable
    )
}

public enum PricingServiceError: Error, Equatable {
    case emptyTable
    case badResponse
}

/// Fetches the LiteLLM price table and folds it under a curated table.
///
/// Implements the existing `PricingTableRefreshing` seam: the `current` table passed
/// in is treated as the curated override set and always wins over the live rows.
public struct LiteLLMPricingTableRefresher: PricingTableRefreshing {
    private let fetcher: @Sendable () async throws -> Data

    public init(fetcher: @escaping @Sendable () async throws -> Data = PricingService.liveFetcher()) {
        self.fetcher = fetcher
    }

    public func refresh(current table: PricingTable) async throws -> PricingTable {
        let data = try await fetcher()
        let liteLLM = PricingService.parseLiteLLM(data)
        guard !liteLLM.isEmpty else { throw PricingServiceError.emptyTable }

        var rates = liteLLM
        for (slug, rate) in table.rates {
            rates[slug] = rate // curated overrides win over the live table
        }
        return PricingTable(rates: rates)
    }
}

/// One slimmed LiteLLM row: the four per-token cost fields, all optional (LiteLLM
/// omits fields a model does not have). Doubles as the on-disk cache row shape.
struct LiteLLMRate: Codable, Sendable, Equatable {
    let inputCostPerToken: Double?
    let outputCostPerToken: Double?
    let cacheReadInputTokenCost: Double?
    let cacheCreationInputTokenCost: Double?

    enum CodingKeys: String, CodingKey {
        case inputCostPerToken = "input_cost_per_token"
        case outputCostPerToken = "output_cost_per_token"
        case cacheReadInputTokenCost = "cache_read_input_token_cost"
        case cacheCreationInputTokenCost = "cache_creation_input_token_cost"
    }

    init(
        inputCostPerToken: Double?,
        outputCostPerToken: Double?,
        cacheReadInputTokenCost: Double?,
        cacheCreationInputTokenCost: Double?
    ) {
        self.inputCostPerToken = inputCostPerToken
        self.outputCostPerToken = outputCostPerToken
        self.cacheReadInputTokenCost = cacheReadInputTokenCost
        self.cacheCreationInputTokenCost = cacheCreationInputTokenCost
    }

    init(perMillion rate: PricingRate) {
        inputCostPerToken = rate.inputPerMillion / 1_000_000
        outputCostPerToken = rate.outputPerMillion / 1_000_000
        cacheReadInputTokenCost = rate.cachedInputPerMillion / 1_000_000
        cacheCreationInputTokenCost = rate.cacheCreationInputPerMillion / 1_000_000
    }

    /// Tolerant decode: a missing or wrong-typed cost field drops to `nil` instead of
    /// failing the whole row, and every non-cost field in the LiteLLM row is ignored.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputCostPerToken = (try? container.decodeIfPresent(Double.self, forKey: .inputCostPerToken)) ?? nil
        outputCostPerToken = (try? container.decodeIfPresent(Double.self, forKey: .outputCostPerToken)) ?? nil
        cacheReadInputTokenCost = (try? container.decodeIfPresent(Double.self, forKey: .cacheReadInputTokenCost)) ?? nil
        cacheCreationInputTokenCost = (try? container.decodeIfPresent(Double.self, forKey: .cacheCreationInputTokenCost)) ?? nil
    }

    /// Converts to a per-million `PricingRate`, or `nil` when the row has no input
    /// price (unusable). Cached reads fall back to the input rate when a model
    /// publishes no discounted cache price.
    var pricingRate: PricingRate? {
        guard let input = inputCostPerToken else { return nil }
        return PricingRate(
            inputPerMillion: input * 1_000_000,
            cachedInputPerMillion: (cacheReadInputTokenCost ?? input) * 1_000_000,
            cacheCreationInputPerMillion: cacheCreationInputTokenCost.map { $0 * 1_000_000 },
            outputPerMillion: (outputCostPerToken ?? 0) * 1_000_000
        )
    }
}

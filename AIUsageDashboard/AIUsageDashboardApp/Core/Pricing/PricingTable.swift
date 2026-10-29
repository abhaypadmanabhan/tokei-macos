import Foundation

public struct PricingRate: Sendable, Equatable {
    public let inputPerMillion: Double
    public let cachedInputPerMillion: Double
    public let cacheCreationInputPerMillion: Double
    public let cacheCreation1hInputPerMillion: Double
    public let outputPerMillion: Double

    public init(
        inputPerMillion: Double,
        cachedInputPerMillion: Double,
        cacheCreationInputPerMillion: Double? = nil,
        outputPerMillion: Double,
        cacheCreation1hInputPerMillion: Double? = nil
    ) {
        self.inputPerMillion = inputPerMillion
        self.cachedInputPerMillion = cachedInputPerMillion
        self.cacheCreationInputPerMillion = cacheCreationInputPerMillion ?? inputPerMillion
        self.outputPerMillion = outputPerMillion
        self.cacheCreation1hInputPerMillion = cacheCreation1hInputPerMillion ?? inputPerMillion * 2
    }
}

public struct PricingTable: Sendable {
    public let rates: [String: PricingRate]

    public init(rates: [String: PricingRate]) {
        var normalizedRates: [String: PricingRate] = [:]
        for (key, rate) in rates {
            normalizedRates[Self.normalizedSlug(key)] = rate
        }
        self.rates = normalizedRates
    }

    /// Exact public rates only. Strip Claude's context variant and dated releases,
    /// but never guess a rate for a newer minor model from a family prefix.
    public func resolveRate(for model: String) -> PricingRate? {
        let key = Self.normalizedSlug(model)
        // Tier stays in the model key so persisted daily maps keep their frozen shape.
        if let marker = key.lastIndex(of: "@"),
           ["priority", "ultrafast", "fast"].contains(String(key[key.index(after: marker)...])) {
            let base = String(key[..<marker])
            let suffix = String(key[marker...])
            guard let standard = resolveRate(for: base) else { return nil }
            return rates[base + suffix] ?? standard
        }
        let slug = key.hasSuffix("[1m]") ? String(key.dropLast(4)) : key
        var candidates = [slug]
        if let slash = slug.lastIndex(of: "/") {
            candidates.append(String(slug[slug.index(after: slash)...]))
        }
        for candidate in candidates {
            if let rate = rates[candidate] { return rate }
        }
        for candidate in candidates {
            guard let dateSuffix = candidate.range(of: "-\\d{8}$", options: .regularExpression),
                  let rate = rates[String(candidate[..<dateSuffix.lowerBound])] else { continue }
            return rate
        }
        return nil
    }

    private static func normalizedSlug(_ slug: String) -> String {
        slug.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }
}

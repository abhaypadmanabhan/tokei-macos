import Foundation

public struct PricingRate: Sendable, Equatable {
    public let inputPerMillion: Double
    public let cachedInputPerMillion: Double
    public let cacheCreationInputPerMillion: Double
    public let outputPerMillion: Double

    public init(
        inputPerMillion: Double,
        cachedInputPerMillion: Double,
        cacheCreationInputPerMillion: Double? = nil,
        outputPerMillion: Double
    ) {
        self.inputPerMillion = inputPerMillion
        self.cachedInputPerMillion = cachedInputPerMillion
        self.cacheCreationInputPerMillion = cacheCreationInputPerMillion ?? inputPerMillion
        self.outputPerMillion = outputPerMillion
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

    /// Resolves a rate for `model`, tolerating newer minor slugs only when a known
    /// table key is a boundary-aligned prefix. Unknown families return nil.
    public func resolveRate(for model: String) -> PricingRate? {
        let candidates = Self.candidates(for: model)
        for candidate in candidates {
            if let rate = rates[candidate] { return rate }
        }

        var bestKey: String?
        for candidate in candidates {
            for key in rates.keys {
                guard Self.isBoundaryAlignedPrefix(key, of: candidate) else { continue }
                if bestKey == nil || key.count > bestKey!.count {
                    bestKey = key
                }
            }
        }
        guard let bestKey else { return nil }
        return rates[bestKey]
    }

    private static func candidates(for model: String) -> [String] {
        let slug = normalizedSlug(model)
        var candidates: [String] = []

        func appendCandidate(_ candidate: String) {
            guard !candidate.isEmpty, !candidates.contains(candidate) else { return }
            candidates.append(candidate)
            if candidate.hasSuffix("-codex") {
                candidates.append(String(candidate.dropLast("-codex".count)))
            }
        }

        appendCandidate(slug)
        if let slash = slug.lastIndex(of: "/") {
            appendCandidate(String(slug[slug.index(after: slash)...]))
        }
        return candidates
    }

    private static func normalizedSlug(_ slug: String) -> String {
        slug
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }

    private static func isBoundaryAlignedPrefix(_ key: String, of slug: String) -> Bool {
        slug == key
            || slug.hasPrefix(key + "-")
            || slug.hasPrefix(key + ".")
            || slug.hasPrefix(key + "_")
            || slug.hasPrefix(key + "/")
            || slug.hasPrefix(key + ":")
    }
}

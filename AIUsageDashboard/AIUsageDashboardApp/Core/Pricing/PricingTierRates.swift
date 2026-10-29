// Tier handling adapted from T3 Code: usagePricing.ts (MIT; THIRD_PARTY_NOTICES.md).
import Foundation

/// Rates use model@tier keys; standard model keys and persisted token shapes stay compatible.
enum PricingTierRates {
    static func read(_ row: [String: Any], standard: PricingRate) -> [String: PricingRate] {
        var result: [String: PricingRate] = [:]
        for tier in ["priority", "ultrafast"] {
            let input = number(row["input_cost_per_token_" + tier]).map { $0 * 1_000_000 }
            let output = number(row["output_cost_per_token_" + tier]).map { $0 * 1_000_000 }
            guard input != nil || output != nil else { continue }
            let ratio = standard.inputPerMillion > 0
                ? (input ?? standard.inputPerMillion) / standard.inputPerMillion : 1
            let scaled = scale(standard, by: ratio)
            let rate = PricingRate(
                inputPerMillion: input ?? scaled.inputPerMillion,
                cachedInputPerMillion: number(row["cache_read_input_token_cost_" + tier])
                    .map { $0 * 1_000_000 } ?? scaled.cachedInputPerMillion,
                cacheCreationInputPerMillion: number(row["cache_creation_input_token_cost_" + tier])
                    .map { $0 * 1_000_000 } ?? scaled.cacheCreationInputPerMillion,
                outputPerMillion: output ?? scaled.outputPerMillion,
                cacheCreation1hInputPerMillion: scaled.cacheCreation1hInputPerMillion
            )
            if valid(rate) { result[tier] = rate }
        }
        if let provider = row["provider_specific_entry"] as? [String: Any],
           let fast = number(provider["fast"]) {
            let rate = scale(standard, by: fast)
            if valid(rate) { result["fast"] = rate }
        }
        return result
    }

    static func scale(_ rate: PricingRate, by multiplier: Double) -> PricingRate {
        PricingRate(inputPerMillion: rate.inputPerMillion * multiplier,
                    cachedInputPerMillion: rate.cachedInputPerMillion * multiplier,
                    cacheCreationInputPerMillion: rate.cacheCreationInputPerMillion * multiplier,
                    outputPerMillion: rate.outputPerMillion * multiplier,
                    cacheCreation1hInputPerMillion: rate.cacheCreation1hInputPerMillion * multiplier)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let number = value.doubleValue
        return number.isFinite && number >= 0 ? number : nil
    }

    private static func valid(_ rate: PricingRate) -> Bool {
        [rate.inputPerMillion, rate.outputPerMillion, rate.cachedInputPerMillion,
         rate.cacheCreationInputPerMillion, rate.cacheCreation1hInputPerMillion]
            .allSatisfy { $0.isFinite && $0 >= 0 && $0 <= LiteLLMRate.maximumPerMillion }
    }
}

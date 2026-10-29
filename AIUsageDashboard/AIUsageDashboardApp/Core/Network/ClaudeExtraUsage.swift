import Foundation

/// Monetary overage is informational; its disabled state stays within bounded source labels.
struct ClaudeExtraUsage: Decodable {
    let isEnabled: Bool?
    let monthlyLimit: Double?
    let usedCredits: Double?
    let currency: String?
    let decimalPlaces: Int?
    let disabledReason: String?

    private enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case currency
        case decimalPlaces = "decimal_places"
        case disabledReason = "disabled_reason"
    }

    func window(providerID: ProviderID) -> QuotaWindow? {
        guard currency == "USD", let monthlyLimit, let usedCredits,
              monthlyLimit.isFinite, usedCredits.isFinite, monthlyLimit > 0, usedCredits >= 0,
              (0...6).contains(decimalPlaces ?? 2) else { return nil }
        let divisor = pow(10, Double(decimalPlaces ?? 2))
        let used = usedCredits / divisor
        let limit = monthlyLimit / divisor
        let enabled = isEnabled == true ? "enabled" : "disabled"
        let reason = disabledReason == "out_of_credits" ? " out_of_credits" : ""
        return QuotaWindow(providerID: providerID, type: .credits, used: used, limit: limit,
                           remaining: limit - used, confidence: .providerReported,
                           source: "api.anthropic.com/api/oauth/usage USD \(enabled)\(reason)",
                           label: "Extra usage", bucketKey: "claude_extra_usage")
    }
}

import Foundation

public final class MaxxerPlanCostStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func monthlyUSD(for providerID: String) -> Double? {
        let amount = defaults.double(forKey: key(for: providerID))
        guard amount.isFinite, amount > 0 else { return nil }
        return amount
    }

    public func setMonthlyUSD(_ amount: Double?, for providerID: String) {
        let key = key(for: providerID)
        guard let amount, amount.isFinite, amount > 0 else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(amount, forKey: key)
    }

    private func key(for providerID: String) -> String {
        "maxxer.planCost.\(providerID)"
    }
}

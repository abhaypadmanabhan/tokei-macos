import Foundation

struct PredictiveQuotaWarning: Sendable {
    struct Key: Codable, Hashable, Sendable {
        let providerID: ProviderID
        let accountID: String?
        let windowType: QuotaWindowType
        let bucketKey: String
        let resetAt: Date
    }

    let key: Key
    let body: String

    static func evaluate(snapshots: [ProviderSnapshot], now: Date) -> [Self] {
        snapshots.flatMap { snapshot in
            snapshot.quotaWindows.compactMap { window in
                guard window.confidence != .unavailable, let reset = window.resetAt, reset > now,
                      let pace = QuotaPace(window: window, now: now),
                      case .runsOut(let runsOut) = pace.forecast else { return nil }
                let lead = reset.timeIntervalSince(runsOut)
                guard lead >= 15 * 60 - 1e-6 else { return nil }
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                formatter.dateStyle = .none
                let interval = lead >= 3600 ? "\(Int(lead / 3600)) h" : "\(Int(lead / 60)) min"
                let name = window.label ?? window.type.rawValue
                return Self(
                    key: Key(
                        providerID: snapshot.providerID,
                        accountID: snapshot.accounts?.first { $0.id == snapshot.headlineAccountID }?.accountID,
                        windowType: window.type,
                        bucketKey: window.bucketKey ?? window.type.rawValue,
                        resetAt: reset
                    ),
                    body: "\(snapshot.displayName) \(name) runs out around \(formatter.string(from: runsOut)), " +
                        "\(interval) before it resets."
                )
            }
        }
    }
}

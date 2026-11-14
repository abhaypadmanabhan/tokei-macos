import Foundation

struct BurnNudgeState: Codable {
    var day: Date?
    var count = 0
    var delivered: [String: Date] = [:]
    var windows: Set<PredictiveQuotaWarning.Key> = []

    init() {}

    private enum CodingKeys: String, CodingKey { case day, count, delivered, windows }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        day = try values.decodeIfPresent(Date.self, forKey: .day)
        count = try values.decodeIfPresent(Int.self, forKey: .count) ?? 0
        delivered = try values.decodeIfPresent([String: Date].self, forKey: .delivered) ?? [:]
        windows = try values.decodeIfPresent(Set<PredictiveQuotaWarning.Key>.self, forKey: .windows) ?? []
    }

    mutating func advance(to now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        if day != today { day = today; count = 0 }
        let oldest = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        delivered = delivered.filter { $0.value >= oldest }
        windows = windows.filter { $0.resetAt.addingTimeInterval(PredictiveQuotaWarning.Key.resetTolerance) >= now }
    }
}

struct BurnNudge {
    let key: String
    let body: String
    let windowKey: PredictiveQuotaWarning.Key?

    static func candidates(snapshot: BurnSnapshot, delivered: [String: Date],
                           windowKeys: Set<PredictiveQuotaWarning.Key>, now: Date) -> [Self] {
        var result: [Self] = []
        let windows = snapshot.expiring.sorted { $0.resetAt < $1.resetAt }
        if let window = windows.first(where: { window in
            guard delivered["window|" + window.id] == nil,
                  !windowKeys.contains(where: { $0.suppresses(window.burnNudgeKey, now: now) }),
                  window.unusedPercent >= 40, window.usedPercent.isFinite,
                  window.confidence == .providerReported || window.confidence == .exact else { return false }
            if let observed = window.observedAt, now.timeIntervalSince(observed) > 30 * 60 { return false }
            let horizon: TimeInterval
            switch window.windowType {
            case .fiveHour, .session, .daily: horizon = 60 * 60
            case .weekly, .monthly: horizon = 6 * 60 * 60
            case .credits, .perModel, .lifetime: return false
            }
            return window.resetAt > now && window.resetAt.timeIntervalSince(now) <= horizon
        }) {
            let label: String
            switch window.windowType {
            case .fiveHour: label = "5-hour"
            case .session: label = "session"
            case .daily: label = "daily"
            case .weekly: label = "weekly"
            case .monthly: label = "monthly"
            case .credits, .perModel, .lifetime: label = ""
            }
            let seconds = window.secondsToReset(from: now)
            let time = seconds < 3_600 ? "\(max(1, Int(ceil(seconds / 60)))) min"
                : "\(Int(ceil(seconds / 3_600))) h"
            result.append(Self(key: "window|" + window.id,
                               body: "\(window.providerName) \(label) window: \(Int(window.unusedPercent.rounded()))% left, " +
                                "resets in \(time). Burn it before it's gone.", windowKey: window.burnNudgeKey))
        }
        for moment in snapshot.moments {
            switch moment {
            case .badge(let badge):
                let rule = badge == .streak7 ? "Seven days at your goal." : badge.rule
                result.append(Self(key: "badge|" + badge.rawValue, body: "New badge: \(badge.title). \(rule)", windowKey: nil))
            case .record(let kind):
                let record: BurnRecord?
                let label: String
                switch kind {
                case .bestDay: record = snapshot.records.bestDay; label = "Best day"
                case .bestWeek: record = snapshot.records.bestWeek; label = "Best week"
                case .bestMonthMultiple: record = snapshot.records.bestMonthMultiple; label = "Best month"
                case .longestStreak: record = snapshot.records.longestStreak; label = "Longest streak"
                }
                if let record {
                    result.append(Self(key: "record|\(kind.rawValue)|\(record.achievedAt.timeIntervalSince1970)",
                                       body: "New record: \(label). Keep burning your plan.", windowKey: nil))
                }
            case .tierUp: break // Tier celebrations stay inside the app.
            }
        }
        var seen = Set<String>()
        return result.filter { delivered[$0.key] == nil && seen.insert($0.key).inserted }
    }
}

private extension ExpiringHeadroom {
    var burnNudgeKey: PredictiveQuotaWarning.Key {
        PredictiveQuotaWarning.Key(providerID: providerID, accountID: accountID, windowType: windowType,
                                   bucketKey: bucketKey, resetAt: resetAt)
    }
}

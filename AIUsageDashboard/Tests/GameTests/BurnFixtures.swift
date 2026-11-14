import Foundation
@testable import AIUsageDashboardCore

struct BurnFixtures {
    var calendar: Calendar
    var now: Date
    let pricing = PricingEngine(table: PricingTable(rates: [
        "test-model": PricingRate(inputPerMillion: 1, cachedInputPerMillion: 0.1, outputPerMillion: 5)
    ]))

    init(zone: String = "UTC", year: Int = 2026, month: Int = 3, day: Int = 9) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        cal.firstWeekday = 2
        calendar = cal
        now = cal.date(from: DateComponents(year: year, month: month, day: day, hour: 15))!
    }

    func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    func snapshot(_ id: ProviderID = .codex, days: [Int: Int], priced: Bool = true,
                  windows: [QuotaWindow] = []) -> ProviderSnapshot {
        let totals = Dictionary(uniqueKeysWithValues: days.map { (day($0.key), $0.value) })
        let models = totals.mapValues { ["test-model": TokenUsage(inputTokens: $0, confidence: .localParsed)] }
        return ProviderSnapshot(providerID: id, displayName: id == .codex ? "Codex" : id.rawValue,
                                authStatus: .authenticated, quotaWindows: windows,
                                todayUsage: TokenUsage(inputTokens: days[0] ?? 0, confidence: .localParsed),
                                weekUsage: .unavailable, lastSyncedAt: now,
                                dailyTotals: totals, dailyModelUsage: priced ? models : nil)
    }

    func sample(type: QuotaWindowType = .fiveHour, used: Double = 90, account: String? = nil,
                reset: Date? = nil, sampledAt: Date? = nil, bucket: String = "five") -> QuotaSample {
        let end = reset ?? day(-1)
        return QuotaSample(providerID: .codex, accountID: account, windowType: type, bucketKey: bucket,
                           usedPercent: used, used: used, limit: 100, resetAt: end,
                           sampledAt: sampledAt ?? end.addingTimeInterval(-60))
    }

    func evaluate(_ snapshots: [ProviderSnapshot], plans: [ProviderID: Double] = [.codex: 31],
                  samples: [QuotaSample] = [], state: BurnState = BurnState(),
                  hidden: Set<ProviderID> = [], emitMoments: Bool = true) -> (snapshot: BurnSnapshot, state: BurnState) {
        BurnEngine.evaluate(snapshots: snapshots, monthlyPlanUSD: plans, quotaSamples: samples, state: state,
                            now: now, calendar: calendar, pricing: pricing,
                            hiddenProviders: hidden, emitMoments: emitMoments)
    }
}

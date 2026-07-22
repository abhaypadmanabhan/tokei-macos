import Foundation

public enum UsageAnalytics {
    public static func streak(
        dailyTotals: [Date: Int],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> (current: Int, longest: Int) {
        let normalized = normalizedDailyTotals(dailyTotals, calendar: calendar)
        let activeDays = Set(normalized.compactMap { $0.value > 0 ? $0.key : nil })
        guard !activeDays.isEmpty else { return (current: 0, longest: 0) }

        let today = calendar.startOfDay(for: now)
        var current = 0
        var cursor = today
        while activeDays.contains(cursor) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        var longest = 0
        var run = 0
        for day in activeDays.sorted() {
            if let previous = calendar.date(byAdding: .day, value: -1, to: day),
               activeDays.contains(previous) {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
        }

        return (current: current, longest: longest)
    }

    public static func bestDay(dailyTotals: [Date: Int]) -> (date: Date, tokens: Int)? {
        dailyTotals
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .first
            .map { (date: $0.key, tokens: $0.value) }
    }

    public static func leastActiveDay(dailyTotals: [Date: Int]) -> (date: Date, tokens: Int)? {
        dailyTotals
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value < rhs.value
            }
            .first
            .map { (date: $0.key, tokens: $0.value) }
    }

    public static func dailyAverage(
        dailyTotals: [Date: Int],
        window: Int? = nil,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Int? {
        let totals = filteredDailyTotals(
            dailyTotals,
            range: window.map { .days($0) } ?? .all,
            calendar: calendar,
            now: now
        )
        guard !totals.isEmpty else { return nil }
        let total = totals.values.reduce(0, +)
        return Int((Double(total) / Double(totals.count)).rounded())
    }

    public static func peakDay(
        dailyTotals: [Date: Int],
        calendar: Calendar = .current
    ) -> (weekday: Int, tokens: Int)? {
        var totalsByWeekday: [Int: Int] = [:]
        for (date, tokens) in dailyTotals where tokens > 0 {
            totalsByWeekday[calendar.component(.weekday, from: date), default: 0] += tokens
        }

        return totalsByWeekday
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .first
            .map { (weekday: $0.key, tokens: $0.value) }
    }

    public static func delta(current: Int?, previous: Int?) -> Double? {
        guard let current, let previous, previous != 0 else { return nil }
        return (Double(current - previous) / Double(previous)) * 100
    }

    public static func providerSplit(
        snapshots: [ProviderSnapshot],
        range: UsageRange,
        calendar: Calendar = .current,
        now: Date = Date(),
        hiddenProviders: Set<ProviderID> = []
    ) -> [(provider: ProviderID, tokens: Int)] {
        snapshots.compactMap { snapshot in
            guard !hiddenProviders.contains(snapshot.providerID) else { return nil }
            let tokens = tokens(for: snapshot, range: range, calendar: calendar, now: now)
            guard tokens > 0 else { return nil }
            return (provider: snapshot.providerID, tokens: tokens)
        }
    }

    public static func rolling(
        snapshots: [ProviderSnapshot],
        calendar: Calendar = .current,
        now: Date = Date(),
        hiddenProviders: Set<ProviderID> = []
    ) -> (sevenDay: Int, thirtyDay: Int, lifetime: Int) {
        let visible = snapshots.filter { !hiddenProviders.contains($0.providerID) }
        return (
            sevenDay: visible.map { tokens(for: $0, range: .sevenDay, calendar: calendar, now: now) }.reduce(0, +),
            thirtyDay: visible.map { tokens(for: $0, range: .thirtyDay, calendar: calendar, now: now) }.reduce(0, +),
            lifetime: visible.map { tokens(for: $0, range: .lifetime, calendar: calendar, now: now) }.reduce(0, +)
        )
    }

    /// Fold per-hour token totals into a fixed 7×24 weekday×hour grid, **restricted
    /// to the requested range**. The hourly buckets carry their own dates, so a slot
    /// only contributes when its calendar day falls inside the same window
    /// `filteredDailyTotals` uses for the trend/stats — otherwise the punch-card would
    /// always show all-time activity while the range control moved everything else
    /// (the 2026-07-21 re-QA bug). `.lifetime` (the default) keeps the all-time fold,
    /// so existing callers are unchanged.
    public static func heatmapMatrix(
        hourlyTotals: [Date: Int],
        range: UsageRange = .lifetime,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [[Int?]] {
        let windowed = filteredHourlyTotals(
            hourlyTotals,
            range: dailyRange(for: range),
            calendar: calendar,
            now: now
        )
        var matrix = Array(repeating: Array<Int?>(repeating: nil, count: 24), count: 7)
        for (date, tokens) in windowed where tokens > 0 {
            let weekdayIndex = calendar.component(.weekday, from: date) - 1
            let hour = calendar.component(.hour, from: date)
            guard matrix.indices.contains(weekdayIndex), matrix[weekdayIndex].indices.contains(hour) else {
                continue
            }
            matrix[weekdayIndex][hour] = (matrix[weekdayIndex][hour] ?? 0) + tokens
        }
        return matrix
    }

    public static func peakHour(
        hourlyTotals: [Date: Int],
        calendar: Calendar = .current
    ) -> (hour: Int, tokens: Int)? {
        var totalsByHour: [Int: Int] = [:]
        for (date, tokens) in hourlyTotals where tokens > 0 {
            totalsByHour[calendar.component(.hour, from: date), default: 0] += tokens
        }

        return totalsByHour
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .first
            .map { (hour: $0.key, tokens: $0.value) }
    }
}

extension UsageAnalytics {
    enum DailyRange {
        case all
        case days(Int)
        case custom(start: Date, end: Date)
        case previousDays(Int)
    }

    static func trend(
        dailyTotals: [Date: Int],
        range: UsageRange,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [(date: Date, tokens: Int)] {
        filteredDailyTotals(dailyTotals, range: dailyRange(for: range), calendar: calendar, now: now)
            .filter { $0.value > 0 }
            .sorted { $0.key < $1.key }
            .map { (date: $0.key, tokens: $0.value) }
    }

    static func aggregateDailyTotals(
        snapshots: [ProviderSnapshot],
        hiddenProviders: Set<ProviderID> = [],
        calendar: Calendar = .current
    ) -> [Date: Int] {
        var totals: [Date: Int] = [:]
        for snapshot in snapshots where !hiddenProviders.contains(snapshot.providerID) {
            guard let dailyTotals = snapshot.dailyTotals else { continue }
            for (date, tokens) in dailyTotals {
                totals[calendar.startOfDay(for: date), default: 0] += tokens
            }
        }
        return totals
    }

    static func total(
        dailyTotals: [Date: Int],
        range: UsageRange,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Int {
        filteredDailyTotals(dailyTotals, range: dailyRange(for: range), calendar: calendar, now: now)
            .values
            .reduce(0, +)
    }

    static func previousTotal(
        dailyTotals: [Date: Int],
        range: UsageRange,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Int? {
        guard let days = dayCount(for: range) else { return nil }
        let previous = filteredDailyTotals(
            dailyTotals,
            range: .previousDays(days),
            calendar: calendar,
            now: now
        )
        guard !previous.isEmpty else { return nil }
        return previous.values.reduce(0, +)
    }

    static func tokens(
        for snapshot: ProviderSnapshot,
        range: UsageRange,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Int {
        if let dailyTotals = snapshot.dailyTotals {
            let total = self.total(dailyTotals: dailyTotals, range: range, calendar: calendar, now: now)
            if total > 0 || dayCount(for: range) != nil || isCustom(range) {
                return total
            }
        }

        switch range {
        case .today:
            return snapshot.todayUsage.totalTokens ?? 0
        case .sevenDay, .week:
            return snapshot.weekUsage.totalTokens ?? 0
        case .thirtyDay, .month:
            return snapshot.monthUsage?.totalTokens ?? 0
        case .ninetyDay:
            return 0
        case .lifetime:
            return snapshot.lifetimeUsage?.totalTokens ?? snapshot.dailyTotals?.values.reduce(0, +) ?? 0
        case .custom:
            return 0
        }
    }

    static func filteredDailyTotals(
        _ dailyTotals: [Date: Int],
        range: DailyRange,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [Date: Int] {
        let normalized = normalizedDailyTotals(dailyTotals, calendar: calendar)
        switch range {
        case .all:
            return normalized
        case .days(let days):
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
            return normalized.filter { $0.key >= start && $0.key <= today }
        case .previousDays(let days):
            let today = calendar.startOfDay(for: now)
            guard let end = calendar.date(byAdding: .day, value: -days, to: today),
                  let start = calendar.date(byAdding: .day, value: -(days * 2 - 1), to: today) else {
                return [:]
            }
            return normalized.filter { $0.key >= start && $0.key <= end }
        case let .custom(start, end):
            let startDay = calendar.startOfDay(for: start)
            let endDay = calendar.startOfDay(for: end)
            return normalized.filter { $0.key >= startDay && $0.key <= endDay }
        }
    }

    /// Filter per-hour buckets to those whose **calendar day** falls in `range`,
    /// preserving each slot's original timestamp (so `heatmapMatrix` keeps its hour
    /// resolution). Parallels `filteredDailyTotals` but never collapses to start-of-day.
    static func filteredHourlyTotals(
        _ hourlyTotals: [Date: Int],
        range: DailyRange,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [Date: Int] {
        switch range {
        case .all:
            return hourlyTotals
        case .days(let days):
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
            return hourlyTotals.filter { slot in
                let day = calendar.startOfDay(for: slot.key)
                return day >= start && day <= today
            }
        case .previousDays(let days):
            let today = calendar.startOfDay(for: now)
            guard let end = calendar.date(byAdding: .day, value: -days, to: today),
                  let start = calendar.date(byAdding: .day, value: -(days * 2 - 1), to: today) else {
                return [:]
            }
            return hourlyTotals.filter { slot in
                let day = calendar.startOfDay(for: slot.key)
                return day >= start && day <= end
            }
        case let .custom(start, end):
            let startDay = calendar.startOfDay(for: start)
            let endDay = calendar.startOfDay(for: end)
            return hourlyTotals.filter { slot in
                let day = calendar.startOfDay(for: slot.key)
                return day >= startDay && day <= endDay
            }
        }
    }

    static func normalizedDailyTotals(_ dailyTotals: [Date: Int], calendar: Calendar) -> [Date: Int] {
        var normalized: [Date: Int] = [:]
        for (date, tokens) in dailyTotals {
            normalized[calendar.startOfDay(for: date), default: 0] += tokens
        }
        return normalized
    }

    static func dayCount(for range: UsageRange) -> Int? {
        switch range {
        case .today: return 1
        case .sevenDay, .week: return 7
        case .thirtyDay, .month: return 30
        case .ninetyDay: return 90
        case .lifetime, .custom: return nil
        }
    }

    static func dailyRange(for range: UsageRange) -> DailyRange {
        switch range {
        case .today: return .days(1)
        case .sevenDay, .week: return .days(7)
        case .thirtyDay, .month: return .days(30)
        case .ninetyDay: return .days(90)
        case .lifetime: return .all
        case let .custom(start, end): return .custom(start: start, end: end)
        }
    }

    static func isCustom(_ range: UsageRange) -> Bool {
        if case .custom = range { return true }
        return false
    }
}

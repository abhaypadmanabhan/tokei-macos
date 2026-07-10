import SwiftUI
import AIUsageDashboardCore

/// Full provider-detail surface (redesign mockup 1): brand header with status
/// pill + last-sync + watching path, TODAY hero with metric tiles, LIMITS bars
/// with a session gauge, the usage-trend line, THIS WEEK stats, and the
/// peak-hour/heatmap pair (honest empty until Phase 1b hourly data lands).
///
/// Wave 1: header, hero tiles, limits, and the trend line are REAL (snapshot
/// state — `dailyTotals` feeds the line). THIS WEEK + hero delta render the
/// `SampleChip`-labeled `DetailAnalyticsFeed.sample` until WP-1's frozen VM
/// props land (Wave 2).
struct ProviderDetailView: View {
    let snapshot: ProviderSnapshot
    var feed: DetailAnalyticsFeed = .sample
    var lastSyncedAt: Date? = nil

    private var tier: ProviderCapabilityTier {
        ProviderCapabilityTier.classify(snapshot)
    }

    /// Daily totals as dated points, oldest→newest, capped to the trailing 30
    /// days so the plot never chokes on lifetime history (spec §9).
    private var trendPoints: [(date: Date, tokens: Int)] {
        guard let totals = snapshot.dailyTotals, !totals.isEmpty else { return [] }
        return totals.sorted { $0.key < $1.key }
            .suffix(30)
            .map { (date: $0.key, tokens: $0.value) }
    }

    private var activeWindows: [QuotaWindow] {
        snapshot.quotaWindows.filter { $0.confidence != .unavailable }
    }

    /// The session (or five-hour) window drives the circular gauge, when present.
    private var gaugeWindow: QuotaWindow? {
        activeWindows.first { $0.type == .session } ?? activeWindows.first { $0.type == .fiveHour }
    }

    private static let syncFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                heroCard
                if !activeWindows.isEmpty {
                    limitsCard
                }
                trendCard
                weekRow
                heatmapCard
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PadzyTheme.ground)
    }

    // MARK: Header (real)

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ProviderBrandMark(snapshot.providerID, size: 38)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(snapshot.displayName.uppercased())
                        .font(.display(size: 20, weight: .black))
                        .foregroundColor(PadzyTheme.ink)
                        .lineLimit(1)
                    statusPill
                }
                Text("WATCHING \(ProviderMetadata.localPaths(for: snapshot.providerID).joined(separator: ", "))")
                    .font(.mono(size: 10))
                    .foregroundColor(PadzyTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text("LAST SYNC")
                    .font(.mono(size: 9))
                    .tracking(0.6)
                    .foregroundColor(PadzyTheme.muted)
                Text(lastSyncedAt.map { Self.syncFormatter.string(from: $0) } ?? "NEVER")
                    .font(.mono(size: 12))
                    .monospacedDigit()
                    .foregroundColor(PadzyTheme.ink)
            }
        }
    }

    /// Capability tier as a quiet hairline pill — status, not action, so it
    /// never takes the accent.
    private var statusPill: some View {
        Text(tier.label)
            .font(.mono(size: 9))
            .tracking(0.6)
            .foregroundColor(PadzyTheme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: PadzyRadius.pill, style: .continuous)
                    .stroke(PadzyTheme.muted.opacity(0.4), lineWidth: 1)
            )
            .fixedSize()
    }

    // MARK: Hero (real values; delta sample until Wave 2)

    private var heroCard: some View {
        SectionCard("Today", trailing: {
            HStack(spacing: 8) {
                if feed.isSample, feed.todayDelta != nil { SampleChip() }
                ConfidenceBadge(confidence: snapshot.todayUsage.confidence)
            }
        }) {
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.todayUsage.totalTokens.map { TokenFormatter.format($0) } ?? "—")
                    .font(.mono(size: 52))
                    .monospacedDigit()
                    .foregroundColor(PadzyTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                if let delta = feed.todayDelta {
                    DeltaLabel(delta: delta, caption: "vs yesterday")
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                StatCard(kicker: "Input", value: format(snapshot.todayUsage.inputTokens))
                StatCard(kicker: "Output", value: format(snapshot.todayUsage.outputTokens))
                StatCard(kicker: "Cache read", value: format(snapshot.todayUsage.cacheReadTokens))
                StatCard(kicker: "Cache write", value: format(snapshot.todayUsage.cacheCreationTokens))
                if let cost = snapshot.costUsage, let amount = cost.amount {
                    StatCard(kicker: "Cost", value: String(format: "$%.2f", amount))
                }
            }
        }
    }

    private func format(_ value: Int?) -> String {
        value.map { TokenFormatter.format($0) } ?? "—"
    }

    // MARK: Limits (real)

    private var limitsCard: some View {
        SectionCard("Limits") {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(activeWindows) { window in
                        limitRow(window)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let gaugeWindow, let used = gaugeWindow.used {
                    CircularGauge(
                        percent: gaugeWindow.limit.map { $0 > 0 ? used / $0 * 100 : used } ?? used,
                        label: "of \(windowLabel(gaugeWindow.type).lowercased()) limit",
                        size: 96
                    )
                }
            }
        }
    }

    private func limitRow(_ window: QuotaWindow) -> some View {
        let percent = window.used ?? 0
        let clamped = max(0, min(100, percent))
        let color = ProviderOverviewRow.thresholdColor(percent)
        let isCritical = ProviderOverviewRow.isCritical(percent)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(windowLabel(window.type) + (window.label.map { " · \($0.uppercased())" } ?? ""))
                    .font(.mono(size: 11))
                    .foregroundColor(PadzyTheme.ink)
                    .lineLimit(1)
                ConfidenceBadge(confidence: window.confidence)
                Spacer(minLength: 8)
                if let resetAt = window.resetAt {
                    Text("RESETS \(ProviderOverviewRow.format(until: resetAt, now: Date()))")
                        .font(.mono(size: 10))
                        .monospacedDigit()
                        .foregroundColor(PadzyTheme.muted)
                }
                HStack(spacing: 3) {
                    if isCritical {
                        Text("!!")
                            .font(.mono(size: 11))
                            .foregroundColor(PadzyTheme.accent)
                    }
                    Text("\(Int(round(percent)))%")
                        .font(.mono(size: 12))
                        .monospacedDigit()
                        .foregroundColor(color)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(PadzyTheme.muted.opacity(0.25))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(clamped / 100.0))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(windowLabel(window.type)) window \(Int(round(percent))) percent used")
    }

    private func windowLabel(_ type: QuotaWindowType) -> String {
        switch type {
        case .fiveHour: return "5-HOUR"
        case .perModel: return "PER MODEL"
        default: return type.rawValue.uppercased()
        }
    }

    // MARK: Trend (real — snapshot.dailyTotals)

    private var trendCard: some View {
        SectionCard("Usage trend", trailing: {
            Text("LAST \(max(trendPoints.count, 2)) DAYS")
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.muted)
        }) {
            LineTrendChart(points: trendPoints)
                .frame(height: 180)
        }
    }

    // MARK: This week + peak hour

    private var weekRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], alignment: .leading, spacing: 16) {
            SectionCard("This week", trailing: {
                if feed.isSample, feed.thisWeek != nil { SampleChip() }
            }) {
                if let week = feed.thisWeek {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                        StatCard(kicker: "Peak day",
                                 value: AnalyticsFormat.weekdayName(week.peakDayWeekday),
                                 deltaCaption: TokenFormatter.format(week.peakDayTokens))
                        StatCard(kicker: "Daily average", value: TokenFormatter.format(week.dailyAverage))
                        if let delta = week.delta {
                            StatCard(kicker: "vs last 7 days", value: "", delta: delta)
                        }
                    }
                } else {
                    emptyNote("NOT ENOUGH HISTORY YET",
                              hint: "Weekly patterns appear after a few days of usage.")
                }
            }

            SectionCard("Peak hour") {
                if let peak = feed.peakHour {
                    StatCard(kicker: "Most active",
                             value: AnalyticsFormat.hourLabel(peak.hour),
                             deltaCaption: TokenFormatter.format(peak.tokens),
                             boxed: false)
                } else {
                    emptyNote("NO HOURLY DATA YET",
                              hint: "Peak hour appears once local logs are parsed with per-hour timestamps.")
                }
            }
        }
    }

    // MARK: Heatmap (honest empty until Phase 1b)

    private var heatmapCard: some View {
        SectionCard("Activity") {
            ActivityHeatmap(matrix: feed.heatmap ?? [])
                .frame(minHeight: 96)
        }
    }

    private func emptyNote(_ headline: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headline)
                .font(.mono(size: 11))
                .tracking(11 * 0.08)
                .foregroundColor(PadzyTheme.ink)
            Text(hint)
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    }
}

// MARK: - Previews

private func previewSnapshot(daysOfHistory: Int) -> ProviderSnapshot {
    let today = Calendar.current.startOfDay(for: Date())
    let values = [4_200_000, 9_800_000, 7_400_000, 15_200_000, 11_100_000,
                  18_600_000, 9_300_000, 21_400_000, 16_800_000, 12_500_000]
    var totals: [Date: Int] = [:]
    for i in 0..<daysOfHistory {
        let day = Calendar.current.date(byAdding: .day, value: -i, to: today) ?? today
        totals[day] = values[i % values.count]
    }
    return ProviderSnapshot(
        providerID: .claudeCode,
        displayName: "Claude Code",
        authStatus: .authenticated,
        quotaWindows: [
            QuotaWindow(providerID: .claudeCode, type: .session, used: 72, limit: 100,
                        resetAt: Date().addingTimeInterval(3 * 3600),
                        confidence: .providerReported, source: "preview"),
            QuotaWindow(providerID: .claudeCode, type: .weekly, used: 94, limit: 100,
                        resetAt: Date().addingTimeInterval(4 * 86_400),
                        confidence: .providerReported, source: "preview"),
        ],
        todayUsage: TokenUsage(inputTokens: 12_400_000, outputTokens: 1_900_000,
                               cacheReadTokens: 48_100_000, cacheCreationTokens: 3_200_000,
                               confidence: .exact),
        weekUsage: TokenUsage(inputTokens: 60_000_000, outputTokens: 9_000_000, confidence: .exact),
        dailyTotals: daysOfHistory > 0 ? totals : nil
    )
}

#Preview("Full data") {
    ProviderDetailView(snapshot: previewSnapshot(daysOfHistory: 14), lastSyncedAt: Date())
        .frame(width: 900, height: 1250)
}

#Preview("Sparse · 1 day, no limits") {
    ProviderDetailView(
        snapshot: ProviderSnapshot(
            providerID: .codex, displayName: "Codex", authStatus: .authenticated,
            todayUsage: TokenUsage(inputTokens: 800_000, outputTokens: 120_000, confidence: .localParsed),
            weekUsage: .unavailable
        ),
        feed: .empty
    )
    .frame(width: 720, height: 900)
}

#Preview("Narrow 640") {
    ProviderDetailView(snapshot: previewSnapshot(daysOfHistory: 7), lastSyncedAt: Date())
        .frame(width: 640, height: 1250)
}

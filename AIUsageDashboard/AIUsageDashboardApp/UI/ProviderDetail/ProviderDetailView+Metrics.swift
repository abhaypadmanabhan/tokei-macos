import SwiftUI
import AIUsageDashboardCore

// The drill-in's measured sections — quota windows, daily history, token split. Kept
// beside the view for the same reason the Accounts section is: `ProviderDetailView.swift`
// stays the surface and its layout, these are the panels it arranges.

extension ProviderDetailView {
    // MARK: 6 · Quota windows

    var quotaWindowsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Quota windows")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(nonCreditsWindows.enumerated()), id: \.offset) { _, window in
                    quotaRow(window)
                }
            }
            HStack(spacing: 8) {
                Rectangle()
                    .fill(PadzyTheme.ink4)
                    .frame(width: 2, height: 11)
                Text("marker = where a steady, linear burn would sit right now")
                    .font(.sans(size: 10.5))
                    .foregroundColor(PadzyTheme.ink5)
            }
            .padding(.top, 6)
        }
    }

    private func quotaRow(_ window: QuotaWindow) -> some View {
        // A window can be present and still carry no `used` — `nonCreditsWindows` filters on
        // confidence, not on having a number. Rendering `?? 0` printed a confident "0%" over
        // an empty bar, which reads as measured headroom; every other unmeasured value on
        // this surface shows an em dash.
        let known = usedPercent(window)
        let pct = known ?? 0
        let pace = known.flatMap {
            MaxxerMath.pace(usedPercent: $0, windowType: window.type,
                            resetAt: window.resetAt, now: Date())
        }
        let verdict = pace.map { PaceVerdict(pct: pct, elapsed: $0.elapsedFraction) }

        return HStack(spacing: 14) {
            Text(windowDisplayName(window))
                .font(.sans(size: 12.5))
                .foregroundColor(PadzyTheme.ink3)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 88, maxWidth: 140, alignment: .leading)

            quotaFillBar(pct: known ?? 0, elapsedFraction: pace?.elapsedFraction,
                         ahead: verdict == .ahead)
                .frame(minWidth: 120, maxWidth: .infinity)

            Text(known.map { "\(Int($0.rounded()))%" } ?? "\u{2014}")
                .font(.mono(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink)
                .frame(width: 44, alignment: .trailing)

            Text(verdict?.word ?? "\u{2014}")
                .font(.sans(size: 10.5, weight: .semibold))
                .foregroundColor(verdict?.color ?? PadzyTheme.ink5)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 64, alignment: .trailing)

            resetCountdown(window.resetAt)
                .frame(width: 92, alignment: .trailing)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(windowDisplayName(window)) \(Int(pct.rounded())) percent used")
    }

    private func quotaFillBar(pct: Double, elapsedFraction: Double?, ahead: Bool) -> some View {
        let clamped = max(0, min(100, pct))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(PadzyTheme.muted.opacity(0.3))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(PadzyTheme.quotaColor(pct))
                    .frame(width: geo.size.width * CGFloat(clamped / 100.0), height: 6)
                if let elapsedFraction {
                    let notchX = geo.size.width * CGFloat(elapsedFraction)
                    Rectangle()
                        .fill(ahead ? PadzyTheme.accent : PadzyTheme.ink.opacity(0.7))
                        .frame(width: 2, height: 10)
                        .offset(x: min(max(0, notchX - 1), geo.size.width - 2))
                        .accessibilityHidden(true)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 10)
    }

    @ViewBuilder
    private func resetCountdown(_ resetAt: Date?) -> some View {
        if let resetAt {
            if reduceMotion {
                countdownLabel(ProviderOverviewRow.format(until: resetAt, now: Date()))
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    countdownLabel(ProviderOverviewRow.format(until: resetAt, now: context.date))
                }
            }
        } else {
            countdownLabel("\u{2014}")
        }
    }

    private func countdownLabel(_ text: String) -> some View {
        Text(text)
            .font(.mono(size: 11))
            .monospacedDigit()
            .foregroundColor(PadzyTheme.ink4)
            .lineLimit(1)
    }

    // MARK: 7 · Daily history

    var dailyHistorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel("Daily history · 30d")
            if trend.count >= 2 {
                LineTrendChart(points: trend, tint: AgentTint.color(snapshot.providerID))
                    .frame(height: 150)
            } else {
                Text("No local token history yet.")
                    .font(.sans(size: 13))
                    .foregroundColor(PadzyTheme.ink4)
            }
        }
    }

    // MARK: 8 · Token split

    private var todaySplitSegments: [(name: String, value: Int, shade: Color)] {
        let today = snapshot.todayUsage
        // Every category `TokenUsage.totalTokens` counts, in one monotonic ink ramp. Reasoning
        // was missing: it counts toward the total but had no segment, so on a provider that
        // reports it (Codex) the bar hid that share and inflated the other four — they still
        // summed to 100%, of a number that was not today's total.
        let defs: [(String, Int?, Color)] = [
            ("Input", today.inputTokens, PadzyTheme.ink2),
            ("Cache read", today.cacheReadTokens, PadzyTheme.ink3),
            ("Cache write", today.cacheCreationTokens, PadzyTheme.ink4),
            ("Reasoning", today.reasoningTokens, PadzyTheme.ink5),
            ("Output", today.outputTokens, Color(hex: "37373E"))
        ]
        return defs.compactMap { name, value, shade in
            guard let value, value > 0 else { return nil }
            return (name, value, shade)
        }
    }

    var hasSplit: Bool { !todaySplitSegments.isEmpty }

    var tokenSplitSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel("Token split · today")
            if hasSplit {
                let segments = todaySplitSegments
                let total = max(1, segments.reduce(0) { $0 + $1.value })
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                            Rectangle()
                                .fill(segment.shade)
                                .frame(width: geo.size.width * CGFloat(Double(segment.value) / Double(total)))
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                FlowLayout(hSpacing: 24, vSpacing: 10) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        splitLegendItem(segment, total: total)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Text("\u{2014}")
                        .font(.mono(size: 16))
                        .foregroundColor(PadzyTheme.ink5)
                    Text("Only aggregate totals available — no per-type split.")
                        .font(.sans(size: 13))
                        .foregroundColor(PadzyTheme.ink4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func splitLegendItem(_ segment: (name: String, value: Int, shade: Color), total: Int) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(segment.shade)
                .frame(width: 8, height: 8)
            Text(segment.name)
                .font(.sans(size: 12.5))
                .foregroundColor(PadzyTheme.ink3)
            Text(TokenFormatter.format(segment.value))
                .font(.mono(size: 12.5))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink)
            Text(String(format: "%.1f%%", Double(segment.value) / Double(total) * 100))
                .font(.mono(size: 11))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink5)
        }
        .fixedSize()
    }
}

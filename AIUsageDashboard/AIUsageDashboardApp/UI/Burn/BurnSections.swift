import SwiftUI
import AIUsageDashboardCore

// The Burn tab's sections below the hero. Each is a plain view over contract values, with its
// own empty state; `BurnView` arranges them.

// MARK: - Use it or lose it

struct ExpiringSection: View {
    let expiring: [ExpiringHeadroom]
    let onSelectProvider: (ProviderID) -> Void

    @Environment(\.dashboardVisible) private var visible

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Use it or lose it")
            if expiring.isEmpty {
                Text("Nothing is about to expire. A window shows up here when it resets soon with a quarter or more unused.")
                    .font(.sans(size: 13))
                    .foregroundColor(PadzyTheme.ink4)
                    .fixedSize(horizontal: false, vertical: true)
            } else if visible {
                // Countdowns tick once a minute, only while Tokei is on screen.
                TimelineView(.everyMinute) { context in rows(now: context.date) }
            } else {
                rows(now: Date())
            }
        }
    }

    private func rows(now: Date) -> some View {
        VStack(spacing: 0) {
            ForEach(expiring) { headroom in
                Button { onSelectProvider(headroom.providerID) } label: {
                    ExpiringRow(headroom: headroom, now: now)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(BurnCopy.expiringSpoken(headroom, now: now))
                .accessibilityHint("Opens \(BurnCopy.agentName(headroom.providerID)) detail")
                if headroom.id != expiring.last?.id { HairlineDivider() }
            }
        }
    }
}

private struct ExpiringRow: View {
    let headroom: ExpiringHeadroom
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            ProviderBrandMark.tinted(headroom.providerID, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(BurnCopy.windowName(headroom))
                    .font(.sans(size: 14, weight: .medium))
                    .foregroundColor(PadzyTheme.ink)
                    .lineLimit(1)
                if let label = headroom.windowLabel, !label.isEmpty {
                    Text(label)
                        .font(.sans(size: 12.5))
                        .foregroundColor(PadzyTheme.ink4)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            UsedBar(usedPercent: headroom.usedPercent)
                .frame(width: 120)
            Text(BurnCopy.percentLeft(headroom))
                .font(.mono(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink)
                .frame(width: 78, alignment: .trailing)
            Text(BurnCopy.countdown(headroom.secondsToReset(from: now)))
                .font(.mono(size: 13.5))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink3)
                .frame(width: 74, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// A used-share bar: the used part in quiet ink, the unused part left as track.
private struct UsedBar: View {
    let usedPercent: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(PadzyTheme.border2)
                Capsule()
                    .fill(PadzyTheme.ink4)
                    .frame(width: proxy.size.width * CGFloat(max(0, min(100, usedPercent)) / 100))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Leaderboard

struct LeaderboardSection: View {
    let entries: [BurnLeaderboardEntry]
    let onSelectProvider: (ProviderID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("This week's agents")
            if entries.isEmpty {
                Text("No agent usage this week yet.")
                    .font(.sans(size: 13))
                    .foregroundColor(PadzyTheme.ink4)
            } else {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        Button { onSelectProvider(entry.providerID) } label: { row(entry) }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel("Rank \(entry.rank), \(BurnCopy.agentName(entry.providerID)), "
                                + "\(BurnCopy.leaderboardValue(entry)), \(BurnCopy.leaderboardTokens(entry))")
                        if entry.id != entries.last?.id { HairlineDivider() }
                    }
                }
            }
        }
    }

    private func row(_ entry: BurnLeaderboardEntry) -> some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.mono(size: 13.5, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(entry.rank == 1 ? PadzyTheme.ink : PadzyTheme.ink4)
                .frame(width: 18, alignment: .leading)
            ProviderBrandMark.tinted(entry.providerID, size: 22)
            Text(BurnCopy.agentName(entry.providerID))
                .font(.sans(size: 14, weight: entry.rank == 1 ? .semibold : .regular))
                .foregroundColor(PadzyTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(BurnCopy.leaderboardValue(entry))
                .font(.mono(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(entry.valueUSD == nil ? PadzyTheme.ink5 : PadzyTheme.ink)
                .help(entry.valueUSD == nil ? "No public rate for this agent's tokens" : "API-equivalent value this week")
            Text(TokenFormatter.format(entry.tokens))
                .font(.mono(size: 13.5))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink4)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

// MARK: - Records

struct RecordsSection: View {
    let records: BurnRecords

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Records")
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 14) {
                GridRow {
                    cell(.bestDay, records.bestDay)
                    cell(.bestWeek, records.bestWeek)
                }
                GridRow {
                    cell(.bestMonthMultiple, records.bestMonthMultiple)
                    cell(.longestStreak, records.longestStreak)
                }
            }
        }
    }

    private func cell(_ kind: BurnRecordKind, _ record: BurnRecord?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(BurnCopy.recordTitle(kind))
                .font(.sans(size: 12.5))
                .foregroundColor(PadzyTheme.ink4)
            Text(BurnCopy.recordValue(record))
                .font(.mono(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(record == nil ? PadzyTheme.ink5 : PadzyTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(record.map { BurnCopy.shortDate($0.achievedAt) } ?? "not yet")
                .font(.mono(size: 12))
                .foregroundColor(PadzyTheme.ink5)
        }
        .frame(minWidth: 120, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(BurnCopy.recordTitle(kind)): \(BurnCopy.recordValue(record))")
    }
}

// MARK: - Left on the table

struct LeftOnTableSection: View {
    let snapshot: BurnSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Left on the table")
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(snapshot.leftOnTablePercent.map { "\(Int($0.rounded()))%" } ?? "—")
                    .font(.mono(size: 34, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(snapshot.leftOnTablePercent == nil ? PadzyTheme.ink5 : PadzyTheme.ink)
                Text(BurnCopy.leftOnTableDetail(snapshot))
                    .font(.sans(size: 13))
                    .foregroundColor(PadzyTheme.ink4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !snapshot.recentWindows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(snapshot.recentWindows.prefix(6)) { outcome in
                        HStack(spacing: 12) {
                            ProviderBrandMark.tinted(outcome.providerID, size: 20)
                            Text("\(BurnCopy.agentName(outcome.providerID)) \(BurnCopy.windowTypeName(outcome.windowType))")
                                .font(.sans(size: 13.5))
                                .foregroundColor(PadzyTheme.ink2)
                            Spacer(minLength: 12)
                            Text("ended \(Int(outcome.finalUsedPercent.rounded()))% used")
                                .font(.mono(size: 13.5))
                                .monospacedDigit()
                                .foregroundColor(outcome.unusedPercent >= 25 ? PadzyTheme.ink : PadzyTheme.ink3)
                            Text(BurnCopy.shortDate(outcome.resetAt))
                                .font(.mono(size: 13.5))
                                .foregroundColor(PadzyTheme.ink5)
                                .frame(width: 56, alignment: .trailing)
                        }
                        .padding(.vertical, 7)
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: 620, alignment: .leading)
            }
        }
    }
}

// MARK: - Tier ladder

struct TierLadderSection: View {
    let tier: MaxxerTier?
    let multiple: Double?
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading("Value tier this month")
            if let multiple, multiple.isFinite, let tier {
                ladder(multiple: multiple, tier: tier)
                Text("\(MaxxerMath.formatMultiple(multiple)) your plans' cost so far. \(tier.blurb)")
                    .font(.sans(size: 13))
                    .foregroundColor(PadzyTheme.ink4)
            } else {
                HStack(spacing: 12) {
                    Text("Set plan costs to see where you sit between Idle and Goblin mode.")
                        .font(.sans(size: 13))
                        .foregroundColor(PadzyTheme.ink4)
                    Button(action: onOpenSettings) {
                        Text("Set plan costs")
                            .font(.sans(size: 13, weight: .medium))
                            .foregroundColor(PadzyTheme.ink)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func ladder(multiple: Double, tier: MaxxerTier) -> some View {
        let position = BurnTierLadder.position(multiple: multiple)
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .topLeading) {
                    // Track in five equal steps, filled up to the user's position.
                    HStack(spacing: 3) {
                        ForEach(BurnTierLadder.thresholds, id: \.self) { _ in
                            Rectangle().fill(PadzyTheme.border2)
                        }
                    }
                    .frame(height: 6)
                    .padding(.top, 22)
                    Rectangle()
                        .fill(PadzyTheme.ink3)
                        .frame(width: width * CGFloat(position), height: 6)
                        .padding(.top, 22)
                    // The marker: the active-state 2 px accent bar with the multiple above it.
                    Text(MaxxerMath.formatMultiple(multiple))
                        .font(.mono(size: 13.5, weight: .semibold))
                        .foregroundColor(PadzyTheme.ink)
                        .fixedSize()
                        .position(x: min(max(20, width * CGFloat(position)), width - 20), y: 8)
                    Rectangle()
                        .fill(PadzyTheme.accent)
                        .frame(width: 2, height: 16)
                        .position(x: min(max(1, width * CGFloat(position)), width - 1), y: 25)
                }
            }
            .frame(height: 32)
            HStack(spacing: 3) {
                ForEach(BurnTierLadder.thresholds, id: \.self) { step in
                    Text(step.tier.displayName)
                        .font(.sans(size: 12.5, weight: step.tier == tier ? .semibold : .regular))
                        .foregroundColor(step.tier == tier ? PadzyTheme.ink : PadzyTheme.ink4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: 720)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tier \(tier.displayName), \(MaxxerMath.formatMultiple(multiple)) of plan cost this month")
    }
}

// MARK: - Badges

struct BadgeGrid: View {
    let badges: [BurnBadgeProgress]
    let celebration: BurnCelebration?
    let onCelebrationFinished: (UUID) -> Void

    private var unlockedCount: Int { badges.filter(\.isUnlocked).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeading("Badges")
                Text("\(unlockedCount) of \(badges.count)")
                    .font(.mono(size: 13.5))
                    .foregroundColor(PadzyTheme.ink4)
                    .fixedSize()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 1)], alignment: .leading, spacing: 1) {
                ForEach(badges) { progress in
                    BadgeCell(progress: progress)
                        .celebration(
                            celebration?.badge == progress.badge ? celebration : nil,
                            spread: 1.3, shape: .cell, onFinish: onCelebrationFinished
                        )
                }
            }
            // Hairline grid: 1 pt gaps over the hairline colour, no cards or shadows.
            .background(PadzyTheme.hairline)
            .overlay(Rectangle().stroke(PadzyTheme.hairline, lineWidth: 1))
        }
    }
}

private struct BadgeCell: View {
    let progress: BurnBadgeProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: BurnCopy.badgeSymbol(progress.badge))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(progress.isUnlocked ? PadzyTheme.ink : PadzyTheme.ink5)
                    .frame(width: 22)
                Text(progress.badge.title)
                    .font(.sans(size: 13.5, weight: .semibold))
                    .foregroundColor(progress.isUnlocked ? PadzyTheme.ink : PadzyTheme.ink3)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !progress.isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(PadzyTheme.ink5)
                        .accessibilityHidden(true)
                }
            }
            Text(progress.badge.rule)
                .font(.sans(size: 12.5))
                .foregroundColor(PadzyTheme.ink4)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if !progress.isUnlocked, let value = progress.progress {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(PadzyTheme.border2)
                            Capsule().fill(PadzyTheme.ink3)
                                .frame(width: proxy.size.width * CGFloat(max(0, min(1, value))))
                        }
                    }
                    .frame(height: 4)
                }
                Text(BurnCopy.badgeStatus(progress))
                    .font(.mono(size: 12))
                    .foregroundColor(progress.isUnlocked ? PadzyTheme.ink3 : PadzyTheme.ink5)
                    .fixedSize()
            }
            .frame(height: 14)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PadzyTheme.ground)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(progress.badge.title). \(BurnCopy.badgeStatus(progress)). \(progress.badge.rule)")
    }
}

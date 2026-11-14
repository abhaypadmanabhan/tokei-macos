import SwiftUI
import AIUsageDashboardCore

/// The Burn tab: today's ring and streak, the plan windows about to expire with room left, this
/// week's agent leaderboard, records, the share of recent windows left unused, the value tier
/// ladder and the badges. Everything is local; the "leaderboard" ranks the user's own agents.
///
/// Reads only `BurnBoard` (observes nothing else), so a loading flag or a range change elsewhere
/// does not re-render it. Every section keeps its place in every state, with plain words when
/// there is nothing to show, so saved → live never reflows the page.
struct BurnView: View {
    @Environment(BurnBoard.self) private var board
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Opens the Settings drawer (plan costs set the goal and the tier).
    var onOpenSettings: () -> Void = {}
    /// Drills into an agent's detail.
    var onSelectProvider: (ProviderID) -> Void = { _ in }

    @State private var sharing = false

    private var snapshot: BurnSnapshot { board.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BurnHero(
                    snapshot: snapshot,
                    momentTitle: board.celebration?.title,
                    celebration: board.celebration.flatMap { $0.badge == nil ? $0 : nil },
                    onShare: { sharing = true },
                    onOpenSettings: onOpenSettings,
                    onCelebrationFinished: { board.finish($0) }
                )
                .padding(.top, 30)
                .padding(.bottom, 28)

                HairlineDivider()
                ExpiringSection(expiring: snapshot.expiring, onSelectProvider: onSelectProvider)
                    .padding(.vertical, 24)

                HairlineDivider()
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 40) {
                        LeaderboardSection(entries: snapshot.leaderboard, onSelectProvider: onSelectProvider)
                            .frame(minWidth: 340, maxWidth: .infinity, alignment: .topLeading)
                        RecordsSection(records: snapshot.records)
                            .frame(width: 300, alignment: .topLeading)
                    }
                    VStack(alignment: .leading, spacing: 28) {
                        LeaderboardSection(entries: snapshot.leaderboard, onSelectProvider: onSelectProvider)
                        RecordsSection(records: snapshot.records)
                    }
                }
                .padding(.vertical, 24)

                HairlineDivider()
                LeftOnTableSection(snapshot: snapshot)
                    .padding(.vertical, 24)

                HairlineDivider()
                TierLadderSection(tier: snapshot.tier, multiple: snapshot.monthValueMultiple, onOpenSettings: onOpenSettings)
                    .padding(.vertical, 24)

                HairlineDivider()
                BadgeGrid(
                    badges: snapshot.badges,
                    celebration: board.celebration.flatMap { $0.badge == nil ? nil : $0 },
                    onCelebrationFinished: { board.finish($0) }
                )
                .padding(.top, 24)

                Text(BurnCopy.eligibilityFinePrint)
                    .font(.sans(size: 12))
                    .foregroundColor(BurnTone.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(.top, 20)
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(.horizontal, PadzySpace.xxl)
            .padding(.bottom, PadzySpace.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $sharing) {
            ShareCardSheet(card: ShareCardModel(snapshot: snapshot), onDone: { sharing = false })
        }
        #if DEBUG
        .task {
            if ProofRoute.wantsShareSheet { sharing = true }
        }
        #endif
    }
}

// MARK: - Hero

private struct BurnHero: View {
    let snapshot: BurnSnapshot
    /// The pending moment's words, badge moments included (their burst plays on the badge).
    let momentTitle: String?
    /// The moment that bursts on the ring: records and tier ups.
    let celebration: BurnCelebration?
    let onShare: () -> Void
    let onOpenSettings: () -> Void
    let onCelebrationFinished: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasGoal: Bool { snapshot.today.goal != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 30) {
                BurnRing(progress: snapshot.today.progress, diameter: 148, lineWidth: 14) {
                    VStack(spacing: 2) {
                        Text(BurnCopy.progressText(snapshot.today.progress))
                            .font(.mono(size: 30, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(hasGoal ? PadzyTheme.ink : BurnTone.caption)
                            .rollingNumber(snapshot.today.progress, reduceMotion: reduceMotion)
                        Text(hasGoal ? "of today's goal" : "no goal yet")
                            .font(.sans(size: 12))
                            .foregroundColor(BurnTone.caption)
                    }
                }
                .celebration(celebration, spread: 1.9, onFinish: onCelebrationFinished)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(hasGoal
                    ? "Today, \(BurnCopy.progressText(snapshot.today.progress)) of the daily goal"
                    : BurnCopy.noGoalTitle)

                facts
                Spacer(minLength: 12)
            }

            Text(BurnCopy.goalSource(snapshot.today.goal))
                .font(.sans(size: 13))
                .foregroundColor(BurnTone.caption)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 560, alignment: .leading)
        }
        .overlay(alignment: .topTrailing) { shareButton }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasGoal {
                VStack(alignment: .leading, spacing: 2) {
                    Text(BurnCopy.todayAmount(snapshot.today))
                        .font(.mono(size: 40, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(PadzyTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .rollingNumber(snapshot.today.valueUSD ?? Double(snapshot.today.tokens), reduceMotion: reduceMotion)
                    Text("burned \(BurnCopy.todayOnPlans), \(BurnCopy.goalPhrase(snapshot.today.goal) ?? "")")
                        .font(.sans(size: 15))
                        .foregroundColor(PadzyTheme.ink3)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(BurnCopy.noGoalTitle)
                        .font(.sans(size: 22, weight: .semibold))
                        .foregroundColor(PadzyTheme.ink)
                    Button(action: onOpenSettings) {
                        Text("Set plan costs")
                            .font(.sans(size: 13, weight: .semibold))
                            .foregroundColor(PadzyTheme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .overlay(
                                RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                                    .stroke(PadzyTheme.border2, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Plan costs set a break-even daily goal")
                }
            }
            streakLine
            momentLine
        }
    }

    private var streakLine: some View {
        let state = BurnCopy.streakState(snapshot.streak)
        return HStack(spacing: 7) {
            Image(systemName: state == .alive ? "flame.fill" : "flame")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(state == .alive ? PadzyTheme.accent : BurnTone.mark)
            Text(BurnCopy.streakTitle(snapshot.streak))
                .font(.sans(size: 15, weight: .semibold))
                .foregroundColor(state == .none ? PadzyTheme.ink3 : PadzyTheme.ink)
            Text(BurnCopy.streakDetail(snapshot.streak))
                .font(.sans(size: 15))
                .foregroundColor(state == .atRisk ? PadzyTheme.warn : BurnTone.caption)
            if snapshot.streak.longest > snapshot.streak.current {
                Text("· longest \(snapshot.streak.longest)")
                    .font(.mono(size: 13.5))
                    .foregroundColor(BurnTone.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Always one line tall: the celebration's words while one plays, else empty. Reserving the
    /// line keeps the hero still when a moment arrives.
    private var momentLine: some View {
        HStack(spacing: 6) {
            if let momentTitle {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PadzyTheme.ink3)
                Text(momentTitle)
                    .font(.sans(size: 14, weight: .medium))
                    .foregroundColor(PadzyTheme.ink)
                    .transition(.opacity)
            }
        }
        .frame(height: 18, alignment: .leading)
        .animation(reduceMotion ? nil : PadzyMotion.quick, value: momentTitle)
    }

    private var shareButton: some View {
        Button(action: onShare) {
            Label("Share my week", systemImage: "square.and.arrow.up")
                .font(.sans(size: 13, weight: .medium))
                .foregroundColor(PadzyTheme.ink2)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                        .stroke(PadzyTheme.border2, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Make an image of this week to post")
    }
}

// MARK: - Previews

#Preview("Burn · sample") {
    BurnView()
        .environment(BurnBoard(snapshot: .sample(now: Date())))
        .frame(width: 1000, height: 1400)
        .background(PadzyTheme.ground)
}

#Preview("Burn · empty") {
    BurnView()
        .environment(BurnBoard(snapshot: .empty(now: Date())))
        .frame(width: 900, height: 1100)
        .background(PadzyTheme.ground)
}

#Preview("Burn · narrow 640") {
    BurnView()
        .environment(BurnBoard(snapshot: .sample(now: Date())))
        .frame(width: 640, height: 1400)
        .background(PadzyTheme.ground)
}

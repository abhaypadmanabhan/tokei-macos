import SwiftUI
import AIUsageDashboardCore

/// The burn strip at the top of the menu bar dropdown: today's ring (a second lap past 1×), the
/// streak and its state, and the window that expires soonest with room left. The whole strip is
/// one button that opens the Burn tab.
///
/// Every line is always present (an honest placeholder when there is nothing to say), so the
/// dropdown keeps its height when the first live sync replaces saved numbers.
struct BurnStrip: View {
    let snapshot: BurnSnapshot
    let celebration: BurnCelebration?
    let onOpen: () -> Void
    let onCelebrationFinished: (UUID) -> Void

    @Environment(\.dashboardVisible) private var visible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var hasGoal: Bool { snapshot.today.goal != nil }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    BurnRing(progress: snapshot.today.progress, diameter: 44, lineWidth: 5, surface: background) {
                        EmptyView()
                    }
                    .celebration(celebration, spread: 2.6, onFinish: onCelebrationFinished)
                    today
                    Spacer(minLength: 8)
                    streak
                }
                expiringLine
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open Burn in Tokei")
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(spokenSummary)
        .accessibilityHint("Opens the Burn tab")
    }

    private var background: Color {
        hovering ? PadzyTheme.hairline : PadzyTheme.menuPanel
    }

    // MARK: Today

    @ViewBuilder
    private var today: some View {
        VStack(alignment: .leading, spacing: 3) {
            if hasGoal {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(BurnCopy.progressText(snapshot.today.progress))
                        .font(.mono(size: 20, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(PadzyTheme.ink)
                        .rollingNumber(snapshot.today.progress, reduceMotion: reduceMotion)
                    Text("of today's goal")
                        .font(.sans(size: 12.5))
                        .foregroundColor(PadzyTheme.ink3)
                }
                Text(BurnCopy.todayAmount(snapshot.today))
                    .font(.mono(size: 12.5))
                    .monospacedDigit()
                    .foregroundColor(PadzyTheme.ink2)
                + Text(" " + (BurnCopy.goalPhrase(snapshot.today.goal) ?? ""))
                    .font(.sans(size: 12.5))
                    .foregroundColor(BurnTone.caption)
            } else {
                Text(BurnCopy.noGoalTitle)
                    .font(.sans(size: 13.5, weight: .semibold))
                    .foregroundColor(PadzyTheme.ink)
                Text("Set plan costs, or use an agent today.")
                    .font(.sans(size: 12.5))
                    .foregroundColor(BurnTone.caption)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .lineLimit(1)
    }

    // MARK: Streak

    private var streak: some View {
        let state = BurnCopy.streakState(snapshot.streak)
        return VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: state == .alive ? "flame.fill" : "flame")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(state == .alive ? PadzyTheme.accent : BurnTone.mark)
                Text("\(snapshot.streak.current)")
                    .font(.mono(size: 20, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(state == .none ? BurnTone.caption : PadzyTheme.ink)
            }
            Text(streakCaption(state))
                .font(.sans(size: 12))
                .foregroundColor(state == .atRisk ? PadzyTheme.warn : BurnTone.caption)
        }
        .fixedSize()
    }

    private func streakCaption(_ state: BurnCopy.StreakState) -> String {
        switch state {
        case .alive: return "day streak"
        case .atRisk: return "keep it alive"
        case .none: return "no streak yet"
        }
    }

    // MARK: Expiring

    /// The top expiring window, ticking once a minute while Tokei is on screen. During a
    /// celebration the same line carries the moment's words, so nothing grows or shifts.
    @ViewBuilder
    private var expiringLine: some View {
        if let celebration {
            line(icon: "sparkles", text: celebration.title, color: PadzyTheme.ink)
        } else if let top = snapshot.expiring.first {
            if visible {
                TimelineView(.everyMinute) { context in
                    line(icon: "hourglass", text: BurnCopy.expiringLine(top, now: context.date), color: PadzyTheme.ink2)
                }
            } else {
                line(icon: "hourglass", text: BurnCopy.expiringLine(top, now: Date()), color: PadzyTheme.ink2)
            }
        } else {
            line(icon: "hourglass", text: BurnCopy.nothingExpiring, color: BurnTone.caption)
        }
    }

    private func line(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(BurnTone.mark)
                .frame(width: 14)
            Text(text)
                .font(.sans(size: 12.5))
                .foregroundColor(color)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var spokenSummary: String {
        var parts: [String] = []
        if hasGoal {
            parts.append("Today \(BurnCopy.progressText(snapshot.today.progress)) of goal, "
                + "\(BurnCopy.todayAmount(snapshot.today)) \(BurnCopy.goalPhrase(snapshot.today.goal) ?? "")")
        } else {
            parts.append(BurnCopy.noGoalTitle)
        }
        parts.append("\(BurnCopy.streakTitle(snapshot.streak)). \(BurnCopy.streakDetail(snapshot.streak))")
        if let top = snapshot.expiring.first {
            parts.append(BurnCopy.expiringSpoken(top, now: Date()))
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Previews

#Preview("Burn strip · sample") {
    BurnStrip(snapshot: .sample(now: Date()), celebration: nil, onOpen: {}, onCelebrationFinished: { _ in })
        .frame(width: 300)
        .background(PadzyTheme.menuPanel)
}

#Preview("Burn strip · empty") {
    BurnStrip(snapshot: .empty(now: Date()), celebration: nil, onOpen: {}, onCelebrationFinished: { _ in })
        .frame(width: 300)
        .background(PadzyTheme.menuPanel)
}

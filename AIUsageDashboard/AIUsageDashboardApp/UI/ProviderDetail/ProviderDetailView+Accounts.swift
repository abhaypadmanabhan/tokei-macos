import SwiftUI
import AIUsageDashboardCore

// The multi-account half of the drill-in: which numbers are one account's and which are
// all of them, the per-account chart and rows, and the notice for the case discovery
// cannot see. Split out of `ProviderDetailView.swift` the way `OverviewView` is split
// from `OverviewViewData` — the view file stays the surface, this file holds the section
// that has its own model.

extension ProviderDetailView {
    var accounts: [ProviderAccountUsage] { snapshot.accounts ?? [] }

    /// Worth a section when there's genuinely more than one account — a single-account setup
    /// would just repeat the headline numbers under a different heading, and its per-account
    /// chart would be the daily-history chart redrawn.
    ///
    /// The one exception: a lone account with a directory we could not read. Then the row is
    /// the only place that says the number above it is missing a piece, which matters more
    /// than not repeating ourselves.
    var showAccounts: Bool {
        accounts.count > 1 || accounts.contains { !$0.unreadableDirectories.isEmpty }
    }
    // MARK: - 4b · Which numbers are all accounts, which are one

    /// The stats above deliberately mix two rules: token counts are a **sum over every
    /// account**, while the gauge and the quota windows are **one account's** — whichever has
    /// the most headroom, because work can be routed there with `CLAUDE_CONFIG_DIR`. Both are
    /// right, and side by side with nothing said they read as one picture: a card showing 50%
    /// while an account sat at 88% is the confusion this line exists to end.
    var accountScopeNote: some View {
        Text(scopeSentence)
            .font(.sans(size: 15))
            .foregroundColor(PadzyTheme.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 640, alignment: .leading)
    }

    private var scopeSentence: String {
        let sum = "Token counts above add up all \(accounts.count) accounts."
        guard tightestWindow != nil else {
            return "\(sum) Per-account numbers are in Accounts below."
        }
        if let account = headlineAccount {
            return "\(sum) The gauge and quota windows are one account — \(account.label), "
                + "the one with the most headroom right now. Per-account numbers are in Accounts below."
        }
        return "\(sum) The gauge and quota windows are a single account's — whichever has the "
            + "most headroom — not all \(accounts.count). Per-account numbers are in Accounts below."
    }

    /// Which account the headline quota came from — **asked**, not re-derived. The provider
    /// picks it and says so on the snapshot; this view only looks the id up. It used to
    /// recompute "lowest peak wins" here and cross-check the answer against the number on
    /// screen, which made the drill-in a second definition of the rule: it excluded credits
    /// windows where the provider does not, so the two could pick different accounts and the
    /// only symptom was this sentence quietly going vague.
    private var headlineAccount: ProviderAccountUsage? {
        guard let id = snapshot.headlineAccountID else { return nil }
        return accounts.first { $0.id == id }
    }

    /// An account's own utilization: the tightest of its non-credits windows.
    private func accountPeak(_ account: ProviderAccountUsage) -> Double? {
        account.quotaWindows
            .filter { $0.type != .credits }
            .compactMap { usedPercent($0) }
            .max()
    }

    /// The other half of multi-account discovery, and the half no detector can reach.
    ///
    /// Accounts are keyed on the Anthropic identity a directory is signed into, never on the
    /// directory itself (`ClaudeAccount.group`) — so a config directory can only ever report
    /// the **one** account it is currently signed into. Two Anthropic logins used one at a
    /// time out of a single `~/.claude` leave **nothing** on disk to tell them apart, so this
    /// person sees one account and no Accounts section, and there is no cleverness that fixes
    /// it — only saying so. This takes the slot the Accounts section would occupy, which is
    /// exactly where someone asking "why is only one of my accounts here?" is already looking.
    ///
    /// If you are here to change the setup notice's copy, read the `// MARK: Copy` block in
    /// `MultiAccountNotice.swift` first: "one account per directory" is wrong and must not
    /// come back.
    ///
    /// Gated on Claude Code (`CLAUDE_CONFIG_DIR` is its mechanism, not a general one) and on
    /// there being local data at all, so a machine that does not run Claude is never told how
    /// to split Claude accounts. Dismissal lives in the notice and is persisted.
    var showAccountSetupNotice: Bool {
        snapshot.providerID == .claudeCode && hasLocalTokenData
    }

    // MARK: 6b · Accounts (multi-account providers)

    /// Per-account breakdown for providers where one machine holds several signed-in accounts
    /// (Claude Code, via `CLAUDE_CONFIG_DIR`): one line per account **over time**, on one
    /// shared scale, plus each account's own totals and its own quota.
    ///
    /// The chart is the point of the section. A single row of current numbers can say which
    /// account is bigger today; it cannot say which one has been climbing all week, which is
    /// what "who is spending more" actually means to someone deciding where to work next.
    var accountsSection: some View {
        let rows = accountRows
        let series = rows.compactMap(\.series)

        return VStack(alignment: .leading, spacing: PadzySpace.m) {
            SectionLabel("Accounts")

            Text(accountsSectionNote)
                .font(.sans(size: 15))
                .foregroundColor(PadzyTheme.ink3)
                .fixedSize(horizontal: false, vertical: true)

            if accounts.count > 1 {
                if series.isEmpty {
                    Text("No per-account history yet \u{2014} Claude's local logs haven't "
                         + "recorded a full day for these accounts.")
                        .font(.sans(size: 15))
                        .foregroundColor(PadzyTheme.ink4)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    AccountTrendChart(series: series)
                        .frame(height: 170)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                if let period = accountPeriodLabel { accountRowsHeader(period) }
                ForEach(rows) { row in
                    accountRow(row)
                }
            }
        }
    }

    private var accountsSectionNote: String {
        guard accounts.count > 1 else {
            return "One account, and one of its directories could not be read \u{2014} "
                + "the totals above are missing whatever is in it."
        }
        let shared = "Each line is one account's own tokens per day, on a shared scale."
        guard let period = accountPeriodLabel else {
            return "\(shared) Daily history below adds every account together."
        }
        // Naming the period twice — here and on the column — is deliberate. The stat tiles at
        // the top of this page are TODAY and these totals are the window; two numbers on one
        // card meaning different things is the whole reason this surface was built.
        return "\(shared) The totals below cover the same \(period) \u{2014} the tiles at the "
            + "top of this page are today. Daily history below adds every account together."
    }

    /// Column header for the account rows. The row's big number is that account's total over
    /// the **chart's** window, and it sits a screen away from a `TOKENS · TODAY` tile — so the
    /// period is stated on the column rather than left to be inferred.
    private func accountRowsHeader(_ period: String) -> some View {
        HStack(spacing: 10) {
            Spacer(minLength: 8)
            Text("tokens \u{00B7} \(period)")
                .font(.sans(size: 15))
                .foregroundColor(PadzyTheme.ink5)
                .lineLimit(1)
            Text("share")
                .font(.sans(size: 15))
                .foregroundColor(PadzyTheme.ink5)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.bottom, PadzySpace.xs)
    }

    /// The span the rows and the chart both cover, in words, derived from the window they are
    /// actually drawn from — so the label cannot claim a period the numbers do not cover.
    private var accountPeriodLabel: String? {
        guard let window = accountWindow else { return nil }
        let days = (Calendar.current.dateComponents(
            [.day], from: window.lowerBound, to: window.upperBound
        ).day ?? 0) + 1
        return days <= 1 ? "today" : "last \(days) days"
    }

    /// One account's row: its identity (and the directories folded into it), its tokens over
    /// the same window as the chart, its share of the accounts' total, and its **own** quota
    /// — the number the gauge above is not, unless this happens to be the freest account.
    private func accountRow(_ row: AccountRow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                StrokeSwatch(color: row.color, dash: row.dash)
                    .opacity(row.series == nil ? 0.35 : 1)
                Text(row.account.label)
                    .font(.sans(size: 15))
                    .foregroundColor(PadzyTheme.ink2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(TokenFormatter.format(row.rangeTokens))
                    .font(.mono(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(row.rangeTokens == nil ? PadzyTheme.ink5 : PadzyTheme.ink)
                Text(row.shareLabel)
                    .font(.mono(size: 13.5))
                    .monospacedDigit()
                    .foregroundColor(PadzyTheme.ink5)
                    .frame(width: 48, alignment: .trailing)
            }

            HStack(alignment: .top, spacing: 10) {
                // One directory per line, never joined. Joined with a separator and truncated
                // in the middle, two long paths lose exactly the separator and read as one
                // path — so the merged identity looks like a directory that vanished, which
                // is the thing this line exists to prevent.
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(row.directoryLabels, id: \.self) { directory in
                        Text(directory)
                            .font(.mono(size: 13.5))
                            .foregroundColor(PadzyTheme.ink5)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                Text("own quota")
                    .font(.sans(size: 15))
                    .foregroundColor(PadzyTheme.ink5)
                Text(row.peak.map { "\(Int($0.rounded()))%" } ?? "\u{2014}")
                    .font(.mono(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(row.peak == nil ? PadzyTheme.ink5 : PadzyTheme.ink2)
                    .frame(width: 44, alignment: .trailing)
            }

            if !row.account.unreadableDirectories.isEmpty {
                Text(Self.unreadableNotice(row.account.unreadableDirectories))
                    .font(.sans(size: 15))
                    .foregroundColor(PadzyTheme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, PadzySpace.s)
        .accessibilityElement(children: .combine)
    }

    /// Names the directory, not just the fact — "something failed" sends nobody anywhere.
    private static func unreadableNotice(_ paths: [String]) -> String {
        let names = paths.map(Self.abbreviated).joined(separator: ", ")
        let subject = paths.count == 1 ? "its usage is" : "their usage is"
        return "\(names) couldn't be read on this refresh, so \(subject) missing from these numbers."
    }

    // MARK: 6b · Per-account series

    private struct AccountRow: Identifiable {
        let account: ProviderAccountUsage
        let color: Color
        let dash: [CGFloat]
        let series: AccountTrendChart.Series?
        /// Tokens inside the chart's window. `nil` when this account has no series at all.
        let rangeTokens: Int?
        let share: Double?
        let peak: Double?

        var id: String { account.id }

        var shareLabel: String {
            guard let share else { return "\u{2014}" }
            return "\(Int((share * 100).rounded()))%"
        }

        /// The `CLAUDE_CONFIG_DIR`s folded into this one identity. Two of them is exactly why
        /// three directories on this machine list as two accounts, and without it the second
        /// row looks like a directory that vanished.
        ///
        /// A list, not a joined string: rendered one per line, a long path can only truncate
        /// inside itself. Joined with a separator and truncated in the middle, two long paths
        /// lose exactly the separator and read as a single directory.
        var directoryLabels: [String] {
            let names = account.configDirectories.map(ProviderDetailView.abbreviated)
            return names.isEmpty ? [ProviderDetailView.abbreviated(account.id)] : names
        }
    }

    /// `~/.claude-account-2` rather than `/Users/me/.claude-account-2` — the home prefix is
    /// the same on every row and eats the width the distinguishing part needs.
    private static func abbreviated(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    /// The day span the per-account chart covers: the aggregate `trend`'s own span, so this
    /// chart and the daily-history chart below it always describe the same window — including
    /// when the user moves the range control, which this view never sees directly. Falls back
    /// to whatever the accounts recorded when the aggregate has no history to align to.
    private var accountWindow: ClosedRange<Date>? {
        let calendar = Calendar.current
        if let first = trend.first?.date, let last = trend.last?.date, first <= last {
            return calendar.startOfDay(for: first)...calendar.startOfDay(for: last)
        }
        let days = accounts
            .flatMap { ($0.dailyTotals ?? [:]).keys }
            .map { calendar.startOfDay(for: $0) }
        guard let first = days.min(), let last = days.max() else { return nil }
        return first...last
    }

    /// Per-account rows, biggest spender first — the answer to the question is the reading
    /// order. Colours stay keyed to the provider's own account order, so a row's line does
    /// not change colour when the ranking flips.
    private var accountRows: [AccountRow] {
        let calendar = Calendar.current
        let tint = AgentTint.color(snapshot.providerID)
        let window = accountWindow

        let rows: [AccountRow] = accounts.enumerated().map { index, account in
            let color = AccountSeriesStyle.color(index, tint: tint)
            let dash = AccountSeriesStyle.dash(index)
            guard let window, let totals = account.dailyTotals, !totals.isEmpty else {
                return AccountRow(account: account, color: color, dash: dash, series: nil,
                                  rangeTokens: nil, share: nil, peak: accountPeak(account))
            }

            var byDay: [Date: Int] = [:]
            for (date, tokens) in totals {
                byDay[calendar.startOfDay(for: date), default: 0] += tokens
            }

            var points: [AccountTrendChart.Point] = []
            var day = window.lowerBound
            while day <= window.upperBound {
                points.append(AccountTrendChart.Point(date: day, tokens: byDay[day] ?? 0))
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }

            let total = points.reduce(0) { $0 + $1.tokens }
            // An account with nothing inside the window gets no line: a flat zero drawn
            // across the whole chart reads as "measured, and it was zero" — which we know,
            // but it also buries the account that did the work under a second stroke.
            let series = total > 0
                ? AccountTrendChart.Series(id: account.id, label: account.label,
                                           color: color, dash: dash, points: points)
                : nil
            return AccountRow(account: account, color: color, dash: dash, series: series,
                              rangeTokens: total, share: nil, peak: accountPeak(account))
        }

        let grandTotal = rows.compactMap(\.rangeTokens).reduce(0, +)
        return rows
            .map { row in
                guard grandTotal > 0, let tokens = row.rangeTokens else { return row }
                return AccountRow(account: row.account, color: row.color, dash: row.dash,
                                  series: row.series, rangeTokens: tokens,
                                  share: Double(tokens) / Double(grandTotal), peak: row.peak)
            }
            .sorted { ($0.rangeTokens ?? -1) > ($1.rangeTokens ?? -1) }
    }

}

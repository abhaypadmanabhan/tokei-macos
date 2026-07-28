import SwiftUI
import AIUsageDashboardCore

/// The one-time "this app does multi-account, and here is what that means" notice.
///
/// Account discovery is entirely automatic and, until this existed, entirely invisible:
/// an `Accounts` section simply materialized inside one provider's drill-in and nothing
/// ever said why, what it meant, or that the feature existed. Two audiences fall out of
/// that, and they are **mutually exclusive by definition**, which is why this is one type
/// with two cases rather than one paragraph:
///
/// - `.discovered` — the machine already has several config directories. Discovery worked;
///   what is missing is *being told*, plus the two aggregation rules (sum vs. one account)
///   that make the numbers read strangely if you have not been told them.
/// - `.claudeSetup` — the machine has several Anthropic logins **sharing one directory**.
///   Nothing on disk distinguishes them, so no amount of detection reaches this person.
///   Telling them how to separate the accounts is the only route that exists.
///
/// The first can only fire when more than one account is found; the second only when fewer
/// than two are. No surface can carry both, so neither tries to.
///
/// Dismissal is persisted and versioned (`…​.v1`, the `tokei.onboarding.seeded.v1` shape),
/// so this is seen once per machine and stays gone — no launch modal, no re-prompt, and a
/// later rewrite of the copy can earn a fresh showing by bumping the version.
struct MultiAccountNotice: View {
    enum Kind {
        /// Several accounts are already being tracked. Carries the provider's display name
        /// and how many were found, so the copy never hardcodes a provider or a count.
        case discovered(provider: String, accounts: Int)
        /// One account is visible and a second may be hidden inside it. Claude-specific:
        /// `CLAUDE_CONFIG_DIR` is Claude Code's mechanism, not a general one.
        case claudeSetup
    }

    let kind: Kind
    /// Optional "take me there" action. `.discovered` uses it to open the provider's
    /// drill-in; `.claudeSetup` has nowhere to go and passes `nil`.
    var actionLabel: String? = nil
    var onAction: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage private var dismissed: Bool

    init(kind: Kind, actionLabel: String? = nil, onAction: (() -> Void)? = nil) {
        self.kind = kind
        self.actionLabel = actionLabel
        self.onAction = onAction
        _dismissed = AppStorage(wrappedValue: false, Self.storageKey(for: kind))
    }

    // MARK: Persistence

    /// Versioned per notice, in the existing `tokei.onboarding.seeded.v1` shape.
    static func storageKey(for kind: Kind) -> String {
        switch kind {
        case .discovered: return "tokei.notice.multiAccount.discovered.v1"
        case .claudeSetup: return "tokei.notice.multiAccount.claudeSetup.v1"
        }
    }

    static func isDismissed(_ kind: Kind, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: storageKey(for: kind))
    }

    // MARK: Copy
    //
    // Every sentence here has to survive the question "can the app actually do that?".
    // It says discovery is per-*directory* rather than per-account, because that is the
    // real mechanism and the reason the second case exists at all.

    private var title: String {
        switch kind {
        case let .discovered(provider, accounts):
            return "Tokei found \(accounts) \(provider) accounts on this Mac"
        case .claudeSetup:
            return "Using more than one Claude account?"
        }
    }

    private var message: String {
        switch kind {
        case let .discovered(provider, accounts):
            return "Nothing to set up — Tokei counts one account per Claude config directory "
                + "and found \(accounts). Token totals add every account together; a quota gauge "
                + "is one account's, whichever has the most headroom right now. "
                + "Open \(provider) to see each account's own usage and quota."
        case .claudeSetup:
            return "Tokei tells accounts apart by their config directory, so two logins taking "
                + "turns in ~/.claude look like one account to it — nothing on disk separates "
                + "them. Give each account a directory of its own and both get tracked:"
        }
    }

    /// The shell line, for `.claudeSetup` only. Mono, selectable, in its own plate.
    private var command: String? {
        switch kind {
        case .discovered: return nil
        case .claudeSetup: return "CLAUDE_CONFIG_DIR=~/.claude-work claude"
        }
    }

    private var footnote: String? {
        switch kind {
        case .discovered: return nil
        case .claudeSetup:
            return "Run it once and sign in. Tokei picks up any ~/.claude-* directory that has "
                + "session logs in it, on the next refresh."
        }
    }

    // MARK: Body

    var body: some View {
        Group {
            if !dismissed { plate }
        }
        .animation(reduceMotion ? nil : PadzyMotion.quick, value: dismissed)
    }

    private var plate: some View {
        VStack(alignment: .leading, spacing: PadzySpace.s) {
            Text(title)
                .font(.sans(size: 15, weight: .semibold))
                .foregroundColor(PadzyTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(.sans(size: 15))
                .foregroundColor(PadzyTheme.ink3)
                .fixedSize(horizontal: false, vertical: true)

            if let command {
                Text(command)
                    .font(.mono(size: 13.5))
                    .foregroundColor(PadzyTheme.ink2)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, PadzySpace.s)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                            .fill(PadzyTheme.ground)
                    )
            }

            if let footnote {
                Text(footnote)
                    .font(.sans(size: 15))
                    .foregroundColor(PadzyTheme.ink4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: PadzySpace.s) {
                if let actionLabel, let onAction {
                    noticeButton(actionLabel, emphasis: true) {
                        dismissed = true
                        onAction()
                    }
                }
                noticeButton("Got it", emphasis: false) { dismissed = true }
                Spacer(minLength: 0)
            }
            .padding(.top, PadzySpace.xs)
        }
        .frame(maxWidth: 620, alignment: .leading)
        .padding(PadzySpace.l)
        .background(
            RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                .fill(PadzyTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                .stroke(PadzyTheme.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityHint(message)
    }

    /// Text buttons in the hairline idiom. Deliberately **no accent**: the accent is
    /// state/action-of-the-view and both surfaces this mounts on already spend theirs
    /// (the Overview metric selector, the detail view's ◆ insight). A notice earning the
    /// loudest colour on the page would be exactly the naggy thing this is not.
    private func noticeButton(
        _ label: String, emphasis: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.sans(size: 15))
                .foregroundColor(emphasis ? PadzyTheme.ink : PadzyTheme.ink3)
                .padding(.horizontal, PadzySpace.m)
                .padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                        .stroke(
                            emphasis ? PadzyTheme.border2 : PadzyTheme.hairline,
                            lineWidth: 1
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Previews

#Preview("Discovered · 2 accounts") {
    MultiAccountNotice(
        kind: .discovered(provider: "Claude Code", accounts: 2),
        actionLabel: "Open Claude Code",
        onAction: {}
    )
    .padding(PadzySpace.xl)
    .frame(width: 760)
    .background(PadzyTheme.ground)
}

#Preview("Claude setup · one directory") {
    MultiAccountNotice(kind: .claudeSetup)
        .padding(PadzySpace.xl)
        .frame(width: 560)
        .background(PadzyTheme.ground)
}

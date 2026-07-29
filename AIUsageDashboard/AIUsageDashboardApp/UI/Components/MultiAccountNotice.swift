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
    var actionLabel: String?
    var onAction: (() -> Void)?

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

    // MARK: Copy
    //
    // Every sentence here has to survive the question "can the app actually do that?".
    // The mechanism it describes is the one discovery actually uses: directories are read,
    // each is asked which Anthropic account it is signed into, and directories answering
    // with the same identity become **one** account. So "one account per directory" is not
    // true and must not be written here — three directories can legitimately be two
    // accounts. What follows from the real mechanism is the limitation the second case
    // exists for: a directory only ever reports the identity it is *currently* signed into.

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
        case let .discovered(provider, _):
            return "Nothing to set up — Tokei asks each Claude config directory which Anthropic "
                + "account it is signed into, then folds directories on the same account into "
                + "one. Several directories can be a single account. Token totals add every "
                + "account together; a quota gauge is one account's, whichever has the most "
                + "headroom right now. Open \(provider) to see each account's own usage, quota, "
                + "and directories."
        case .claudeSetup:
            return "A config directory reports the one account it is currently signed into, so "
                + "two logins taking turns in ~/.claude look like a single account — nothing on "
                + "disk separates them. Give each account a directory of its own and both get "
                + "tracked:"
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
            // The prose is ONE VoiceOver stop, the buttons stay their own. `.combine` merges
            // these four into a single element; `.contain` (what this used to be) leaves them
            // individually accessible *and* adds a container label and hint on top, so the
            // title and the whole paragraph get announced twice. The buttons are deliberately
            // outside this element: `.combine` demotes child buttons to actions on the
            // rotor, and "dismissible" is a stated requirement of this notice, so `Got it`
            // stays a directly focusable button.
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
            }
            .accessibilityElement(children: .combine)

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

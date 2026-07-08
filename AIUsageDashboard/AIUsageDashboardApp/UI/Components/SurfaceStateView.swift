import SwiftUI

/// Reusable data-state surface — loading / empty / error — in the aitracker theme.
///
/// Editorial contract: numbered mono kicker + hairline, display-face headline in
/// `ink`, mono/`muted` supporting copy, and the single accent reserved for the
/// running-state tick (loading), the `!!` error signal, and the primary recovery
/// action. Status is never signalled by colour alone. Every data surface routes
/// its non-loaded states through this one view so the three states read
/// identically across the app.
struct SurfaceStateView: View {
    enum Kind {
        /// Running/sync in progress. `message` is a terse status line.
        case loading(message: String)
        /// No data yet. `headline` states the fact, `hint` gives the next action.
        case empty(headline: String, hint: String)
        /// Recoverable failure. `headline` labels it, `detail` explains it.
        case error(headline: String, detail: String)
    }

    /// Optional numbered editorial kicker (`02`, `USAGE`). Suppressed in compact mode.
    var kicker: (number: String, title: String)? = nil
    let kind: Kind
    /// Dense variant for the menu-bar popover: no kicker, tighter type, no full-height fill.
    var compact: Bool = false
    /// Recovery action for `.error`; renders a primary accent button when present.
    var onRetry: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 14) {
            if let kicker, !compact {
                EditorialKicker(number: kicker.number, title: kicker.title)
                HairlineDivider()
            }
            content
            if !compact { Spacer(minLength: 0) }
        }
        .padding(compact ? 0 : 28)
        .frame(
            maxWidth: .infinity,
            maxHeight: compact ? nil : .infinity,
            alignment: .topLeading
        )
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case let .loading(message):
            HStack(spacing: 10) {
                // Running-state accent tick; pulses unless Reduce Motion is on.
                Rectangle()
                    .fill(PadzyTheme.accent)
                    .frame(width: compact ? 5 : 7, height: compact ? 5 : 7)
                    .opacity(reduceMotion ? 1.0 : (pulse ? 0.2 : 1.0))
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }
                Text(message.uppercased())
                    .font(.mono(size: compact ? 11 : 13))
                    .foregroundColor(PadzyTheme.muted)
            }

        case let .empty(headline, hint):
            VStack(alignment: .leading, spacing: compact ? 4 : 8) {
                Text(headline.uppercased())
                    .font(.display(size: compact ? 12 : 18, weight: .black))
                    .foregroundColor(PadzyTheme.ink)
                Text(hint)
                    .font(.mono(size: compact ? 10 : 12))
                    .foregroundColor(PadzyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case let .error(headline, detail):
            VStack(alignment: .leading, spacing: compact ? 4 : 10) {
                HStack(spacing: 8) {
                    // Non-colour error signal so status never depends on hue alone.
                    Text("!!")
                        .font(.mono(size: compact ? 11 : 13))
                        .foregroundColor(PadzyTheme.accent)
                    Text(headline.uppercased())
                        .font(.display(size: compact ? 12 : 18, weight: .black))
                        .foregroundColor(PadzyTheme.ink)
                }
                Text(detail)
                    .font(.mono(size: compact ? 10 : 12))
                    .foregroundColor(PadzyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let onRetry {
                    Button(action: onRetry) {
                        Text("RETRY")
                            .font(.mono(size: compact ? 10 : 12))
                            .foregroundColor(PadzyTheme.ground)
                            .padding(.horizontal, compact ? 12 : 20)
                            .padding(.vertical, compact ? 5 : 8)
                            .background(PadzyTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, compact ? 2 : 4)
                    .accessibilityLabel("Retry sync")
                }
            }
        }
    }
}

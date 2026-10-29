import SwiftUI

/// Reusable data-state surface — loading / empty / error — in the aitracker theme.
///
/// Editorial contract: a sentence-case headline in `ink`, supporting copy in the body font
/// and `muted`, and the single accent reserved for the
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

    let kind: Kind
    /// Dense variant for the menu-bar popover: no header, tighter type, no full-height fill.
    var compact: Bool = false
    /// Recovery action for `.error`; renders a primary accent button when present.
    var onRetry: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 14) {
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
                Text(message)
                    .font(.sans(size: compact ? 12 : 15))
                    .foregroundColor(PadzyTheme.muted)
            }

        case let .empty(headline, hint):
            VStack(alignment: .leading, spacing: compact ? 4 : 8) {
                Text(headline)
                    .font(.sans(size: compact ? 13 : 17, weight: .semibold))
                    .foregroundColor(PadzyTheme.ink)
                Text(hint)
                    .font(.sans(size: compact ? 12 : 15))
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
                    Text(headline)
                        .font(.sans(size: compact ? 13 : 17, weight: .semibold))
                        .foregroundColor(PadzyTheme.ink)
                }
                Text(detail)
                    .font(.sans(size: compact ? 12 : 15))
                    .foregroundColor(PadzyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let onRetry {
                    Button(action: onRetry) {
                        Text("Retry")
                            .font(.sans(size: compact ? 12 : 13, weight: .semibold))
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

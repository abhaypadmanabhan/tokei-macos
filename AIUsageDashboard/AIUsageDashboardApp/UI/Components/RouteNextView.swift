import SwiftUI
import AIUsageDashboardCore

/// "Send work here next": the top row of `RoutePlan` with its reason, and the next plans on
/// demand. Drawn in the menu bar popover (`compact`) and on Overview. Plain ink only: the
/// popover's one accent stays on Open Tokei, and a plan to avoid says "Avoid" in words.
struct RouteNextView: View {
    let suggestion: RouteSuggestion
    var compact = false
    /// The popover names the section itself; Overview puts a `SectionHeading` above.
    var showsHeading = false

    @State private var expanded = RouteNextView.startsExpanded
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var bodySize: CGFloat { compact ? 12.5 : 15 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : PadzySpace.s) {
            if showsHeading {
                Text(RouteSuggestion.heading)
                    .font(.sans(size: 12.5))
                    .foregroundColor(PadzyTheme.ink3)
                    .accessibilityAddTraits(.isHeader)
            }
            summary
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(suggestion.spoken)
            if !suggestion.others.isEmpty {
                disclosure
                if expanded {
                    VStack(alignment: .leading, spacing: compact ? 6 : PadzySpace.s) {
                        ForEach(suggestion.others) { line(for: $0) }
                    }
                    .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var summary: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : PadzySpace.xs) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let target = suggestion.target {
                    ProviderBrandMark.tinted(target, size: compact ? 16 : 18)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                }
                Text(suggestion.title)
                    .font(.sans(size: compact ? 13.5 : 17, weight: .semibold))
                    .foregroundColor(suggestion.state == .recommend ? PadzyTheme.ink : PadzyTheme.ink2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let window = suggestion.window {
                    Text(window)
                        .font(.sans(size: bodySize))
                        .foregroundColor(PadzyTheme.ink4)
                        .lineLimit(1)
                }
            }
            Text(suggestion.detail)
                .font(.sans(size: bodySize))
                .foregroundColor(PadzyTheme.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var disclosure: some View {
        Button {
            withAnimation(reduceMotion ? nil : PadzyMotion.quick) { expanded.toggle() }
        } label: {
            HStack(spacing: 5) {
                Text(expanded ? "Hide the rest" : moreLabel)
                    .font(.sans(size: compact ? 12 : 13, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: compact ? 9 : 10, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .foregroundColor(PadzyTheme.ink2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? "Hide the other plans" : moreLabel)
    }

    private var moreLabel: String {
        let count = suggestion.others.count
        if suggestion.state != .recommend { return count == 1 ? "Show the plan" : "Show the \(count) plans" }
        return count == 1 ? "Show the next plan" : "Show the next \(count)"
    }

    private func line(for line: RouteSuggestion.Line) -> some View {
        HStack(spacing: 8) {
            ProviderBrandMark.tinted(line.providerID, size: compact ? 14 : 16)
            Text(line.name)
                .font(.sans(size: bodySize))
                .foregroundColor(PadzyTheme.ink2)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(compact ? line.shortStatus : line.status)
                .font(.mono(size: compact ? 11 : 13))
                .monospacedDigit()
                .foregroundColor(line.avoid ? PadzyTheme.ink3 : PadzyTheme.ink4)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(line.name), \(line.status.replacingOccurrences(of: " · ", with: ", "))")
    }
}

extension RouteNextView {
    /// Debug captures only: `-TokeiProofRouteExpanded YES` opens the next plans.
    static var startsExpanded: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "TokeiProofRouteExpanded")
        #else
        return false
        #endif
    }
}

extension DashboardViewModel {
    /// The route over the agents the person shows, at this moment. The one source for the
    /// "Send work here next" row and the tile and drill-in chips.
    var routeSuggestion: RouteSuggestion {
        let now = Date()
        let visible = ProviderVisibility.visible(snapshots)
        return RouteSuggestion.make(RoutePlan.make(snapshots: visible, now: now), snapshots: visible, now: now)
    }
}

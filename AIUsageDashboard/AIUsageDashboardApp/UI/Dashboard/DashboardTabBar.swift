import SwiftUI
import AIUsageDashboardCore

/// The dashboard's top bar: in-content tab pills, the shared time-range control,
/// and the Settings gear. Replaces the 230pt sidebar's OVERVIEW / VALUE /
/// SETTINGS rows.
///
/// Each pill is a numbered mono kicker over one live number, so the tab strip is
/// also the top-level KPI row — navigation and data in the same 56pt instead of
/// a column of chrome. Active state is the 2px accent tick under the pill (the
/// only accent on this surface); an inactive pill is muted, never a second hue.
struct DashboardTabBar: View {
    /// One pill's live number. `isKnown == false` renders the value muted, which
    /// is how "—" reads as "not computable" rather than as a small number.
    struct Stat: Equatable {
        let value: String
        let caption: String
        var isKnown: Bool = true
    }

    /// The active tab, or `nil` while a drill-in pane (provider / settings /
    /// connections) owns the content.
    let activeTab: DashboardTab?
    let stats: [DashboardTab: Stat]
    let isSettingsActive: Bool
    /// Whether the range control governs the current pane (Overview + provider
    /// detail). Hidden elsewhere rather than shown as a control that does nothing.
    let showsRangeSelector: Bool
    @Binding var range: UsageRange
    let onSelect: (DashboardTab) -> Void
    let onOpenSettings: () -> Void

    private static let rangeOptions: [(range: UsageRange, label: String)] = [
        (.sevenDay, "7D"),
        (.thirtyDay, "30D"),
        (.ninetyDay, "90D"),
    ]

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(DashboardTab.allCases) { tab in
                pill(tab)
            }

            Spacer(minLength: 12)

            HStack(spacing: 12) {
                if showsRangeSelector {
                    TimeRangeSelector(range: $range, options: Self.rangeOptions)
                }
                gearButton
            }
            .padding(.trailing, 20)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    // MARK: Tab pill

    private func pill(_ tab: DashboardTab) -> some View {
        let isActive = activeTab == tab
        let stat = stats[tab]
        return Button(action: { onSelect(tab) }) {
            VStack(alignment: .leading, spacing: 5) {
                Text(tab.kicker)
                    .font(.mono(size: 11))
                    .tracking(11 * 0.08)
                    .foregroundColor(isActive ? PadzyTheme.ink : PadzyTheme.muted)
                    .lineLimit(1)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(stat?.value ?? "—")
                        .font(.mono(size: 17))
                        .monospacedDigit()
                        .foregroundColor(statColor(isActive: isActive, isKnown: stat?.isKnown ?? false))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let caption = stat?.caption, !caption.isEmpty {
                        Text(caption.uppercased())
                            .font(.mono(size: 9))
                            .tracking(0.4)
                            .foregroundColor(PadzyTheme.muted)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isActive ? PadzyTheme.accent : Color.clear)
                    .frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(tab.accessibilityName) tab, \(stat?.value ?? "no value") \(stat?.caption ?? "")")
    }

    /// An unknown value stays muted even on the active tab — dimness is the
    /// signal that the number could not be computed.
    private func statColor(isActive: Bool, isKnown: Bool) -> Color {
        guard isKnown else { return PadzyTheme.muted }
        return isActive ? PadzyTheme.ink : PadzyTheme.ink.opacity(0.7)
    }

    // MARK: Gear

    private var gearButton: some View {
        Button(action: onOpenSettings) {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(isSettingsActive ? PadzyTheme.ink : PadzyTheme.muted)
                .frame(width: 30, height: 26)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isSettingsActive ? PadzyTheme.accent : Color.clear)
                        .frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(",", modifiers: .command)
        .accessibilityLabel("Settings")
        .accessibilityAddTraits(isSettingsActive ? [.isButton, .isSelected] : .isButton)
    }
}

/// Shared time-range control (Posh inline-range pattern): one selector in the top
/// bar governing the whole pane, instead of a per-card copy. Hairline-bounded,
/// 2px accent tick under the active option — accent as state, never as a data hue.
struct TimeRangeSelector: View {
    @Binding var range: UsageRange
    let options: [(range: UsageRange, label: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.label) { option in
                let isSelected = range == option.range
                Button {
                    range = option.range
                } label: {
                    Text(option.label)
                        .font(.mono(size: 11))
                        .foregroundColor(isSelected ? PadzyTheme.ink : PadzyTheme.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(isSelected ? PadzyTheme.accent : Color.clear)
                                .frame(height: 2)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                .fill(PadzyTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                .stroke(PadzyTheme.muted.opacity(0.25), lineWidth: 1)
        )
        .fixedSize()
    }
}

// MARK: - Previews

private struct TabBarPreview: View {
    @State private var range: UsageRange = .sevenDay
    let activeTab: DashboardTab?
    let isSettingsActive: Bool
    var stats: [DashboardTab: DashboardTabBar.Stat] = [
        .overview: .init(value: "533.6M", caption: "today"),
        .value: .init(value: "3.4×", caption: "plan value"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            DashboardTabBar(
                activeTab: activeTab,
                stats: stats,
                isSettingsActive: isSettingsActive,
                showsRangeSelector: activeTab != .value && !isSettingsActive,
                range: $range,
                onSelect: { _ in },
                onOpenSettings: {}
            )
            HairlineDivider()
        }
        .background(PadzyTheme.ground)
    }
}

#Preview("Tab bar · overview active") {
    TabBarPreview(activeTab: .overview, isSettingsActive: false).frame(width: 900)
}

#Preview("Tab bar · value active") {
    TabBarPreview(activeTab: .value, isSettingsActive: false).frame(width: 900)
}

#Preview("Tab bar · settings active, unknown stats") {
    TabBarPreview(
        activeTab: nil,
        isSettingsActive: true,
        stats: [
            .overview: .init(value: "—", caption: "today", isKnown: false),
            .value: .init(value: "—", caption: "plan value", isKnown: false),
        ]
    )
    .frame(width: 640)
}

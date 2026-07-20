import SwiftUI
import AIUsageDashboardCore

/// The dashboard's top bar: three plain in-content tabs, the shared time-range
/// control, and the Settings gear. Replaces the 230pt sidebar's OVERVIEW / VALUE /
/// SETTINGS rows.
///
/// The mockup made these tabs pure navigation — a plain word, no numbered kicker
/// and no live number (those moved into the content). Active state is the 2px
/// accent tick under the label (the only accent on this surface); an inactive tab
/// is muted, never a second hue.
struct DashboardTabBar: View {
    /// The active tab, or `nil` while a drill-in pane (provider / settings) owns
    /// the content.
    let activeTab: DashboardTab?
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
        HStack(alignment: .center, spacing: 0) {
            HStack(spacing: 20) {
                ForEach(DashboardTab.allCases) { tab in
                    tabButton(tab)
                }
            }

            Spacer(minLength: 16)

            HStack(spacing: 16) {
                if showsRangeSelector {
                    TimeRangeSelector(range: $range, options: Self.rangeOptions)
                }
                gearButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    // MARK: Tab

    private func tabButton(_ tab: DashboardTab) -> some View {
        let isActive = activeTab == tab
        return Button(action: { onSelect(tab) }) {
            Text(tab.label)
                .font(.sans(size: 14, weight: .medium))
                .foregroundColor(isActive ? PadzyTheme.ink : PadzyTheme.ink5)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isActive ? PadzyTheme.accent : Color.clear)
                        .frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(tab.accessibilityName) tab")
    }

    // MARK: Gear

    private var gearButton: some View {
        Button(action: onOpenSettings) {
            Image(systemName: "gearshape")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(isSettingsActive ? PadzyTheme.accent : PadzyTheme.ink5)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(",", modifiers: .command)
        .accessibilityLabel("Settings")
        .accessibilityAddTraits(isSettingsActive ? [.isButton, .isSelected] : .isButton)
    }
}

/// Shared time-range control, restyled to the mockup's plain range chips: text-only
/// buttons (no bordered box), mono numerals, the active option in primary ink over
/// a faint fill — accent is reserved for the tabs' active tick, never spent here.
struct TimeRangeSelector: View {
    @Binding var range: UsageRange
    let options: [(range: UsageRange, label: String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.label) { option in
                let isSelected = range == option.range
                Button {
                    range = option.range
                } label: {
                    Text(option.label)
                        .font(.mono(size: 11.5, weight: .medium))
                        .foregroundColor(isSelected ? PadzyTheme.ink : PadzyTheme.ink5)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                                .fill(isSelected ? PadzyTheme.window : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .fixedSize()
    }
}

// MARK: - Previews

private struct TabBarPreview: View {
    @State private var range: UsageRange = .sevenDay
    let activeTab: DashboardTab?
    let isSettingsActive: Bool

    var body: some View {
        VStack(spacing: 0) {
            DashboardTabBar(
                activeTab: activeTab,
                isSettingsActive: isSettingsActive,
                showsRangeSelector: activeTab == .overview,
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

#Preview("Tab bar · agents active") {
    TabBarPreview(activeTab: .agents, isSettingsActive: false).frame(width: 900)
}

#Preview("Tab bar · settings active") {
    TabBarPreview(activeTab: nil, isSettingsActive: true).frame(width: 640)
}

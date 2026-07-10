import SwiftUI
import AIUsageDashboardCore

/// In-app Settings surface (redesign mockup 2): a 6-card grid — Agents, Data
/// Sources, Limits & Alerts, Appearance, Notifications, Advanced — rendered
/// inside the dashboard's right pane. Controls with real backing state are
/// live; everything without a store renders an honest disabled "SOON" chip —
/// never faked persistence.
struct SettingsPane: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    /// What the system menu-bar item shows (#38/#40). Shared key with `MenuBarLabel`.
    @AppStorage(MenuBarDisplayMode.storageKey)
    private var menuBarModeRaw = MenuBarDisplayMode.todayTokens.rawValue

    private var menuBarMode: MenuBarDisplayMode {
        MenuBarDisplayMode(rawValue: menuBarModeRaw) ?? .todayTokens
    }

    /// Same environment view model as the dashboard (SettingsPane renders inside it),
    /// so a Rescan can immediately re-run the providers.
    @EnvironmentObject private var viewModel: DashboardViewModel

    /// Routes to the Connections screen, where per-provider live-quota toggles live.
    let onOpenConnections: () -> Void
    /// Opens the `+` add-agent sheet.
    var onAddAgent: () -> Void = {}

    // Bundle version can't change at runtime — compute once.
    private static let appVersion: String =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                HairlineDivider()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16)],
                          alignment: .leading, spacing: 16) {
                    agentsCard
                    dataSourcesCard
                    limitsAlertsCard
                    appearanceCard
                    notificationsCard
                    advancedCard
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PadzyTheme.ground)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SETTINGS")
                    .font(.display(size: 22, weight: .black))
                    .foregroundColor(PadzyTheme.ink)
                Text("Local-first. Everything here is read from your machine — nothing leaves it.")
                    .font(.mono(size: 11))
                    .foregroundColor(PadzyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            // Config presets/export have no backing store yet — honest disabled.
            disabledPillButton("PRESET: DEFAULT")
            disabledPillButton("EXPORT CONFIG")
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: 1 · Agents

    private var agentsCard: some View {
        SectionCard("Agents") {
            HStack(spacing: 10) {
                AddAgentButton { onAddAgent() }
                linkButton("MANAGE CONNECTIONS →", action: onOpenConnections)
            }

            // Strict grid: fixed 24pt mark column · left-aligned SHOW label ·
            // spacer · toggle right-flush (PadzyToggleStyle's fixed-width track),
            // so every row shares the same left edge and toggle x-position.
            VStack(spacing: 8) {
                ForEach(ProviderID.allCases, id: \.self) { providerID in
                    HStack(spacing: 10) {
                        ProviderMark(providerID, size: 16)
                            .frame(width: 24, height: 24)
                        ProviderVisibilityToggleRow(
                            providerID: providerID,
                            displayName: viewModel.snapshot(for: providerID)?.displayName
                                ?? providerID.rawValue.replacingOccurrences(of: "_", with: " ")
                        )
                    }
                }
            }

            comingSoonRow("DRAG TO REORDER SIDEBAR")

            Text("Hidden agents are skipped in the sidebar, menu bar, and keyboard navigation.")
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 2 · Data Sources

    /// Honest per-provider source disclosure: the exact path Tokei reads, the
    /// on-disk format, and whether the provider currently yields data.
    private var dataSourcesCard: some View {
        SectionCard("Data Sources", trailing: {
            Button(action: { Task { await viewModel.refresh() } }) {
                Text("RESCAN")
                    .font(.mono(size: 10))
                    .foregroundColor(PadzyTheme.ground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                            .fill(PadzyTheme.accent)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .accessibilityLabel("Rescan all data sources")
        }) {
            VStack(spacing: 10) {
                ForEach(ProviderID.allCases, id: \.self) { providerID in
                    dataSourceRow(providerID)
                }
            }
            comingSoonRow("ADD CUSTOM SOURCE")
        }
    }

    private func dataSourceRow(_ providerID: ProviderID) -> some View {
        let snapshot = viewModel.snapshot(for: providerID)
        let watching = viewModel.isAvailable(providerID)
        let path = ProviderMetadata.localPaths(for: providerID).first ?? "—"

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text((snapshot?.displayName ?? providerID.rawValue.replacingOccurrences(of: "_", with: " ")).uppercased())
                        .font(.display(size: 11, weight: .bold))
                        .foregroundColor(PadzyTheme.ink)
                    formatChip(for: path)
                }
                Text(path)
                    .font(.mono(size: 9))
                    .foregroundColor(PadzyTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(watching ? "WATCHING" : "NO DATA")
                .font(.mono(size: 9))
                .tracking(0.4)
                .foregroundColor(watching ? PadzyTheme.ink : PadzyTheme.muted)
        }
    }

    /// On-disk format chip derived from the verified source path.
    private func formatChip(for path: String) -> some View {
        let format = path.hasSuffix(".vscdb") ? "SQLITE" : "LOGS"
        return Text(format)
            .font(.mono(size: 8))
            .tracking(0.4)
            .foregroundColor(PadzyTheme.muted)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(PadzyTheme.muted.opacity(0.4), lineWidth: 1)
            )
    }

    // MARK: 3 · Limits & Alerts

    private var limitsAlertsCard: some View {
        SectionCard("Limits & Alerts") {
            Toggle(isOn: $notificationsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("QUOTA ALERTS")
                        .font(.display(size: 12, weight: .bold))
                        .foregroundColor(PadzyTheme.ink)
                    Text("Notifies when any provider window crosses 80% or 95%.")
                        .font(.mono(size: 10))
                        .foregroundColor(PadzyTheme.muted)
                }
            }
            .toggleStyle(.padzy)

            HairlineDivider()

            // No monthly-limit or threshold store exists yet — honest disabled.
            comingSoonRow("MONTHLY TOKEN LIMIT")
            disabledSegmentRow(options: ["OFF", "90%", "80%", "70%", "CUSTOM"], selected: 0)
            disabledSegmentRow(options: ["BANNER", "EMAIL", "BOTH"], selected: 0)
        }
    }

    // MARK: 4 · Appearance

    private var appearanceCard: some View {
        SectionCard("Appearance") {
            // Theme previews: Dark ships; OLED/Light have no theme store yet.
            HStack(spacing: 10) {
                themePreview(name: "DARK", ground: PadzyTheme.ground, active: true)
                themePreview(name: "OLED", ground: Color.black, active: false)
                themePreview(name: "LIGHT", ground: Color(hex: "F4F4F6"), active: false)
            }

            HStack(spacing: 8) {
                Text("ACCENT")
                    .font(.mono(size: 10))
                    .foregroundColor(PadzyTheme.muted)
                accentSwatch(PadzyTheme.accent, active: true)
                ForEach(["4C86FF", "3DBE8B", "A46BFF", "E8912D"], id: \.self) { hex in
                    accentSwatch(Color(hex: hex), active: false)
                }
                ComingSoonChip()
            }

            HairlineDivider()

            // Menu-bar display mode — real, shared key with MenuBarLabel.
            VStack(alignment: .leading, spacing: 6) {
                Text("MENU BAR SHOWS")
                    .font(.mono(size: 10))
                    .foregroundColor(PadzyTheme.muted)
                HStack(spacing: 0) {
                    ForEach(Array(MenuBarDisplayMode.allCases.enumerated()), id: \.element.id) { index, mode in
                        let isSelected = menuBarMode == mode
                        Button {
                            menuBarModeRaw = mode.rawValue
                        } label: {
                            Text(mode.title.uppercased())
                                .font(.mono(size: 10))
                                .foregroundColor(isSelected ? PadzyTheme.ink : PadzyTheme.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(isSelected ? PadzyTheme.accent : Color.clear)
                                        .frame(height: 2)
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)

                        if index < MenuBarDisplayMode.allCases.count - 1 {
                            Rectangle()
                                .fill(PadzyTheme.muted.opacity(0.3))
                                .frame(width: 1)
                        }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                        .stroke(PadzyTheme.muted.opacity(0.3), lineWidth: 1)
                )
                Text(menuBarMode.hint)
                    .font(.mono(size: 10))
                    .foregroundColor(PadzyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func themePreview(name: String, ground: Color, active: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                    .fill(ground)
                VStack(alignment: .leading, spacing: 3) {
                    RoundedRectangle(cornerRadius: 2).fill(PadzyTheme.accent).frame(width: 18, height: 3)
                    RoundedRectangle(cornerRadius: 2).fill(PadzyTheme.muted.opacity(0.6)).frame(width: 34, height: 3)
                    RoundedRectangle(cornerRadius: 2).fill(PadzyTheme.muted.opacity(0.35)).frame(width: 26, height: 3)
                }
                .padding(8)
            }
            .frame(height: 52)
            .overlay(
                RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                    .stroke(active ? PadzyTheme.accent : PadzyTheme.muted.opacity(0.3),
                            lineWidth: active ? 1.5 : 1)
            )

            HStack(spacing: 4) {
                Text(name)
                    .font(.mono(size: 9))
                    .foregroundColor(active ? PadzyTheme.ink : PadzyTheme.muted)
                if !active { ComingSoonChip() }
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(active ? 1 : 0.55)
        .accessibilityLabel("\(name) theme\(active ? ", active" : ", coming soon")")
    }

    private func accentSwatch(_ color: Color, active: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .overlay(
                Circle().stroke(active ? PadzyTheme.ink : Color.clear, lineWidth: 1.5)
            )
            .opacity(active ? 1 : 0.4)
            .accessibilityHidden(true)
    }

    // MARK: 5 · Notifications

    private var notificationsCard: some View {
        SectionCard("Notifications") {
            Toggle(isOn: $notificationsEnabled) {
                Text("LIMIT APPROACHING / EXCEEDED")
                    .font(.mono(size: 11))
                    .foregroundColor(PadzyTheme.ink)
            }
            .toggleStyle(.padzy)

            Text("One switch backs both thresholds today (80% approaching, 95% exceeded).")
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HairlineDivider()

            comingSoonRow("DAILY SUMMARY")
            comingSoonRow("SYNC ISSUES")
            comingSoonRow("NEW FEATURES")
        }
    }

    // MARK: 6 · Advanced

    private var advancedCard: some View {
        SectionCard("Advanced") {
            VStack(alignment: .leading, spacing: 8) {
                Text("AUTO-SYNC · FILE WATCHER")
                    .font(.display(size: 12, weight: .bold))
                    .foregroundColor(PadzyTheme.ink)
                Text("WATCHING ~/.claude · ~/.codex · ~/.cline · 2S DEBOUNCE")
                    .font(.mono(size: 10))
                    .foregroundColor(PadzyTheme.muted)
                Text("Refreshes whenever an agent writes new session logs. Manual sync: \u{2318}R.")
                    .font(.mono(size: 10))
                    .foregroundColor(PadzyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HairlineDivider()

            linkButton("CHECK FOR UPDATES") {
                AppDelegate.shared?.checkForUpdates()
            }

            comingSoonRow("EXPORT USAGE DATA")
            comingSoonRow("RESET ALL DATA")

            HairlineDivider()

            VStack(alignment: .leading, spacing: 4) {
                Text("TOKEI")
                    .font(.display(size: 14, weight: .black))
                    .foregroundColor(PadzyTheme.ink)
                Text("LOCAL-FIRST AI USAGE · v\(Self.appVersion)")
                    .font(.mono(size: 10))
                    .foregroundColor(PadzyTheme.muted)
                Text("All data is read locally from your machine — nothing leaves it.")
                    .font(.mono(size: 10))
                    .foregroundColor(PadzyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Building blocks

    /// A hairline-bounded text action, styled to match the sidebar entries.
    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.mono(size: 11))
                .foregroundColor(PadzyTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .overlay(
                    RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                        .stroke(PadzyTheme.muted.opacity(0.5), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }

    /// Row for a control that has no backing store yet — visibly disabled with a
    /// SOON chip; renders nothing interactive, persists nothing.
    private func comingSoonRow(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.mono(size: 11))
                .foregroundColor(PadzyTheme.muted)
            ComingSoonChip()
            Spacer(minLength: 0)
        }
        .opacity(0.7)
        .accessibilityLabel("\(title), coming soon")
    }

    /// Disabled segmented placeholder mirroring the mockup's threshold/channel
    /// pickers — visually present, honestly inert until a store exists.
    private func disabledSegmentRow(options: [String], selected: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Text(option)
                    .font(.mono(size: 10))
                    .foregroundColor(index == selected ? PadzyTheme.ink : PadzyTheme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                if index < options.count - 1 {
                    Rectangle()
                        .fill(PadzyTheme.muted.opacity(0.25))
                        .frame(width: 1)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                .stroke(PadzyTheme.muted.opacity(0.25), lineWidth: 1)
        )
        .opacity(0.5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func disabledPillButton(_ title: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.muted)
            ComingSoonChip()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(
            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                .stroke(PadzyTheme.muted.opacity(0.3), lineWidth: 1)
        )
        .opacity(0.7)
        .accessibilityLabel("\(title), coming soon")
    }
}

/// Caps-mono "SOON" tag for controls that exist in the design but have no
/// backing store yet.
struct ComingSoonChip: View {
    var body: some View {
        Text("SOON")
            .font(.mono(size: 8))
            .tracking(0.6)
            .foregroundColor(PadzyTheme.muted)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(PadzyTheme.muted.opacity(0.45), lineWidth: 1)
            )
            .fixedSize()
    }
}

// MARK: - Previews

@MainActor
private func mockVM(_ ids: [ProviderID]) -> DashboardViewModel {
    let vm = DashboardViewModel()
    vm.snapshots = ids.map {
        ProviderSnapshot(providerID: $0, displayName: $0.rawValue.replacingOccurrences(of: "_", with: " ").capitalized,
                         authStatus: .authenticated, quotaWindows: [],
                         todayUsage: .unavailable, weekUsage: .unavailable, warnings: [])
    }
    return vm
}

#Preview("Settings · wide") {
    SettingsPane(onOpenConnections: {}, onAddAgent: {})
        .environmentObject(mockVM(ProviderID.allCases))
        .frame(width: 980, height: 1100)
        .background(PadzyTheme.ground)
}

#Preview("Settings · narrow 640") {
    SettingsPane(onOpenConnections: {}, onAddAgent: {})
        .environmentObject(mockVM(ProviderID.allCases))
        .frame(width: 640, height: 1200)
        .background(PadzyTheme.ground)
}

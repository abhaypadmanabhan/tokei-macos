import SwiftUI
import AIUsageDashboardCore

/// In-app Settings surface. Renders inside the dashboard's right pane (not a separate
/// macOS Settings window), so new configuration can grow here over time. Reached from
/// the bottom-pinned SETTINGS entry in the provider sidebar and from the menu bar.
///
/// Revamp (#39): real information hierarchy — a page title over grouped, hairline-
/// bounded sections, each with a clean unnumbered header, a one-line intent, polished
/// control rows, and honest supporting copy. No numbered kicker, no flat SaaS list.
struct SettingsPane: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    /// Same environment view model as the dashboard (SettingsPane renders inside it),
    /// so toggling a data-source setting can immediately re-run the providers.
    @EnvironmentObject private var viewModel: DashboardViewModel

    /// Routes to the Connections screen, where per-provider live-quota toggles
    /// now live (moved out of Settings so each connection gets its own
    /// detect/connect/enable flow).
    let onOpenConnections: () -> Void
    /// Opens the `+` add-agent sheet.
    var onAddAgent: () -> Void = {}

    // Bundle version can't change at runtime — compute once.
    private static let appVersion: String =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SETTINGS")
                        .font(.display(size: 22, weight: .black))
                        .foregroundColor(PadzyTheme.ink)
                    Text("Local-first. Everything here is read from your machine — nothing leaves it.")
                        .font(.mono(size: 11))
                        .foregroundColor(PadzyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 20)

                HairlineDivider()

                VStack(alignment: .leading, spacing: 24) {
                    agentsSection
                    alertsSection
                    refreshSection
                    aboutSection
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)

                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PadzyTheme.ground)
    }

    // MARK: Sections

    private var agentsSection: some View {
        section("Agents", intro: "Choose which coding agents appear on your dashboard. Adding an agent makes it visible; removing just hides it — nothing is deleted.") {
            HStack(spacing: 10) {
                AddAgentButton { onAddAgent() }
                linkButton("MANAGE CONNECTIONS →", action: onOpenConnections)
            }
            .padding(.bottom, 4)

            ForEach(ProviderID.allCases, id: \.self) { providerID in
                ProviderVisibilityToggleRow(
                    providerID: providerID,
                    displayName: viewModel.snapshot(for: providerID)?.displayName
                        ?? providerID.rawValue.replacingOccurrences(of: "_", with: " ")
                )
            }

            Text("Hidden agents are skipped in the sidebar, menu bar, and keyboard navigation. Live network/RPC quota for Cursor, Antigravity, and Claude is enabled per-agent in Connections.")
                .font(.mono(size: 11))
                .foregroundColor(PadzyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private var alertsSection: some View {
        section("Quota alerts", intro: "Get notified before a plan runs out.") {
            Toggle(isOn: $notificationsEnabled) {
                Text("QUOTA ALERTS")
                    .font(.display(size: 12, weight: .bold))
                    .foregroundColor(PadzyTheme.ink)
            }
            .toggleStyle(.switch)
            .tint(PadzyTheme.accent)

            Text("Tokei posts a notification when any provider quota window crosses 80% or 95%.")
                .font(.mono(size: 11))
                .foregroundColor(PadzyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var refreshSection: some View {
        section("Refresh", intro: "How usage stays current.") {
            Text("AUTO-SYNC · FILE WATCHER")
                .font(.display(size: 12, weight: .bold))
                .foregroundColor(PadzyTheme.ink)

            Text("WATCHING ~/.claude · ~/.codex · ~/.cline · 2S DEBOUNCE")
                .font(.mono(size: 11))
                .foregroundColor(PadzyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Text("Tokei refreshes automatically whenever an agent writes new session logs. Manual sync: \u{2318}R in the dashboard.")
                .font(.mono(size: 11))
                .foregroundColor(PadzyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var aboutSection: some View {
        section("About", intro: nil) {
            Text("TOKEI")
                .font(.display(size: 16, weight: .black))
                .foregroundColor(PadzyTheme.ink)

            Text("LOCAL-FIRST AI USAGE · v\(Self.appVersion)")
                .font(.mono(size: 11))
                .foregroundColor(PadzyTheme.muted)

            Text("All data is read locally from your machine — nothing leaves it. Built under the Padzy OS design system.")
                .font(.mono(size: 11))
                .foregroundColor(PadzyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Building blocks

    /// A labeled settings block: clean unnumbered header + one-line intent over a
    /// hairline-bounded surface. `intro` is optional for terminal sections.
    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        intro: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(title)
                if let intro {
                    Text(intro)
                        .font(.mono(size: 11))
                        .foregroundColor(PadzyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 10, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(PadzyTheme.surface)
                .overlay(Rectangle().stroke(PadzyTheme.muted.opacity(0.3), lineWidth: 1))
        }
    }

    /// A hairline-bounded text action, styled to match the sidebar entries.
    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.mono(size: 11))
                .foregroundColor(PadzyTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .overlay(Rectangle().stroke(PadzyTheme.muted.opacity(0.5), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
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

#Preview("Settings") {
    SettingsPane(onOpenConnections: {}, onAddAgent: {})
        .environmentObject(mockVM(ProviderID.allCases))
        .frame(width: 760, height: 640)
        .background(PadzyTheme.ground)
}

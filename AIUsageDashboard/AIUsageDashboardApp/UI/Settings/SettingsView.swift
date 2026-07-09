import SwiftUI
import AIUsageDashboardCore

/// In-app Settings surface. Renders inside the dashboard's right pane (not a separate
/// macOS Settings window), so new configuration can grow here over time. Reached from
/// the bottom-pinned SETTINGS entry in the provider sidebar and from the menu bar.
struct SettingsPane: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    /// Same environment view model as the dashboard (SettingsPane renders inside it),
    /// so toggling a data-source setting can immediately re-run the providers.
    @EnvironmentObject private var viewModel: DashboardViewModel

    /// Routes to the Connections screen, where per-provider live-quota toggles
    /// now live (moved out of Settings so each connection gets its own
    /// detect/connect/enable flow).
    let onOpenConnections: () -> Void

    // Bundle version can't change at runtime — compute once.
    private static let appVersion: String =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    EditorialKicker(number: "02", title: "SETTINGS")
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 20)

                HairlineDivider()

                VStack(alignment: .leading, spacing: 20) {
                    section(number: "01", title: "PROVIDERS") {
                        ForEach(ProviderID.allCases, id: \.self) { providerID in
                            ProviderVisibilityToggleRow(
                                providerID: providerID,
                                displayName: providerID.rawValue.replacingOccurrences(of: "_", with: " ")
                            )
                        }

                        Text("HIDDEN PROVIDERS ARE SKIPPED IN THE SIDEBAR, MENU BAR, AND KEYBOARD NAVIGATION.")
                            .font(.mono(size: 11))
                            .foregroundColor(PadzyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)

                        HairlineDivider()
                            .padding(.vertical, 8)

                        Text("Live network/RPC quota fetching for Cursor, Antigravity, and Claude is managed in Connections.")
                            .font(.system(size: 11))
                            .foregroundColor(PadzyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(action: onOpenConnections) {
                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: 2)
                                Text("MANAGE CONNECTIONS →")
                                    .font(.display(size: 13, weight: .bold))
                                    .foregroundColor(PadzyTheme.ink)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                Spacer(minLength: 0)
                            }
                            .background(PadzyTheme.surface)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(.isButton)
                        .padding(.top, 4)
                    }

                    section(number: "02", title: "QUOTA ALERTS") {
                        Toggle(isOn: $notificationsEnabled) {
                            Text("QUOTA ALERTS")
                                .font(.display(size: 12, weight: .bold))
                                .foregroundColor(PadzyTheme.ink)
                        }
                        .toggleStyle(.switch)
                        .tint(PadzyTheme.accent)

                        Text("ALERTS AT 80% / 95%")
                            .font(.mono(size: 11))
                            .foregroundColor(PadzyTheme.muted)

                        Text("Tokei posts a notification when any provider quota window crosses 80% or 95%.")
                            .font(.system(size: 11))
                            .foregroundColor(PadzyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    section(number: "03", title: "REFRESH INTERVAL") {
                        Text("AUTO-SYNC: FILE WATCHER")
                            .font(.display(size: 12, weight: .bold))
                            .foregroundColor(PadzyTheme.ink)

                        Text("WATCHING ~/.claude  ·  ~/.codex  ·  ~/.cline  ·  2S DEBOUNCE")
                            .font(.mono(size: 11))
                            .foregroundColor(PadzyTheme.muted)

                        Text("Tokei refreshes automatically whenever a provider writes new session logs. Manual sync: \u{2318}R in the dashboard.")
                            .font(.system(size: 11))
                            .foregroundColor(PadzyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    section(number: "04", title: "ABOUT") {
                        Text("TOKEI")
                            .font(.display(size: 16, weight: .black))
                            .foregroundColor(PadzyTheme.ink)

                        Text("LOCAL-FIRST AI USAGE  ·  v\(Self.appVersion)")
                            .font(.mono(size: 11))
                            .foregroundColor(PadzyTheme.muted)

                        Text("All data is read locally from your machine — nothing leaves it. Built under the Padzy OS design system.")
                            .font(.system(size: 11))
                            .foregroundColor(PadzyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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

    /// A labeled settings block: numbered mono kicker over a hairline-bordered surface.
    @ViewBuilder
    private func section<Content: View>(
        number: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorialKicker(number: number, title: title)
            VStack(alignment: .leading, spacing: 8, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(PadzyTheme.surface)
                .border(PadzyTheme.muted.opacity(0.3), width: 1)
        }
    }
}

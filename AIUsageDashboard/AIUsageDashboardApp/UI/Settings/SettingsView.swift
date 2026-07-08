import SwiftUI
import AIUsageDashboardCore

/// In-app Settings surface. Renders inside the dashboard's right pane (not a separate
/// macOS Settings window), so new configuration can grow here over time. Reached from
/// the bottom-pinned SETTINGS entry in the provider sidebar and from the menu bar.
struct SettingsPane: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    /// Read by the Cursor connector directly (`UserDefaults.standard.bool(forKey:)`) —
    /// this is the one sanctioned switch for the network-usage path (Bible §"WP-2 · B").
    /// Default OFF: Cursor never makes a network request unless the user opts in here.
    @AppStorage("cursorNetworkUsageEnabled") private var cursorNetworkUsageEnabled = false
    /// Read by the Antigravity connector directly, mirroring the Cursor switch above.
    /// Default OFF: no local RPC call to the running Antigravity app unless opted in.
    @AppStorage("antigravityOnlineQuotaEnabled") private var antigravityOnlineQuotaEnabled = false

    /// Same environment view model as the dashboard (SettingsPane renders inside it),
    /// so toggling a data-source setting can immediately re-run the providers.
    @EnvironmentObject private var viewModel: DashboardViewModel

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

                        Toggle(isOn: $cursorNetworkUsageEnabled) {
                            Text("CURSOR: FETCH USAGE ONLINE")
                                .font(.display(size: 12, weight: .bold))
                                .foregroundColor(PadzyTheme.ink)
                        }
                        .toggleStyle(.switch)
                        .tint(PadzyTheme.accent)
                        // The Cursor connector reads this flag at fetch time; a plain
                        // UserDefaults write triggers no sync, so re-run the providers
                        // now — otherwise flipping the switch appears to "do nothing"
                        // until the next file-watcher event.
                        .onChange(of: cursorNetworkUsageEnabled) {
                            Task { await viewModel.refresh() }
                        }

                        Text("Makes an authenticated request to Cursor's servers using your local session token to fetch real token/quota usage. Off by default — Cursor otherwise reports plan/tier and accepted-lines from local data only, with no network access.")
                            .font(.system(size: 11))
                            .foregroundColor(PadzyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        HairlineDivider()
                            .padding(.vertical, 8)

                        Toggle(isOn: $antigravityOnlineQuotaEnabled) {
                            Text("ANTIGRAVITY: FETCH QUOTA ONLINE")
                                .font(.display(size: 12, weight: .bold))
                                .foregroundColor(PadzyTheme.ink)
                        }
                        .toggleStyle(.switch)
                        .tint(PadzyTheme.accent)
                        .onChange(of: antigravityOnlineQuotaEnabled) {
                            Task { await viewModel.refresh() }
                        }

                        Text("Reads live quota from the running Antigravity app on your Mac. No token is stored or sent anywhere. Requires Antigravity to be open.")
                            .font(.system(size: 11))
                            .foregroundColor(PadzyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
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

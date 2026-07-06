import SwiftUI

/// In-app Settings surface. Renders inside the dashboard's right pane (not a separate
/// macOS Settings window), so new configuration can grow here over time. Reached from
/// the bottom-pinned SETTINGS entry in the provider sidebar and from the menu bar.
struct SettingsPane: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

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
                    section(number: "01", title: "QUOTA ALERTS") {
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

                    section(number: "02", title: "REFRESH INTERVAL") {
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

                    section(number: "03", title: "ABOUT") {
                        Text("TOKEI")
                            .font(.display(size: 16, weight: .black))
                            .foregroundColor(PadzyTheme.ink)

                        Text("LOCAL-FIRST AI USAGE  ·  v\(appVersion)")
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

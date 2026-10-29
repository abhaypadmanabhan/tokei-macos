import ServiceManagement
import SwiftUI
import AIUsageDashboardCore

// The Settings drawer's live-quota, alert and login-item sections. Their own file because
// each is a self-contained block with its own store; `SettingsDrawer.swift` arranges them.

/// One switch per provider that can read live quota over the network (from
/// `ProviderMetadata`, so Gemini's `geminiNetworkUsageEnabled` lives here too). The switch
/// is the same key the provider reads at fetch time; a change re-syncs at once.
struct LiveQuotaSettingsSection: View {
    let providers: [ProviderID]
    let displayName: (ProviderID) -> String
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PadzySpace.m) {
            SectionLabel("Live quota")
            Text("Off means local logs only for that agent: no request leaves your Mac for it.")
                .font(.sans(size: 11))
                .foregroundColor(PadzyTheme.ink5)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: PadzySpace.s) {
                ForEach(providers, id: \.self) { id in
                    if let key = ProviderMetadata.liveQuotaEnabledKey(for: id) {
                        LiveQuotaToggleRow(providerID: id, name: displayName(id), key: key, onChange: onChange)
                    }
                }
            }
        }
    }
}

private struct LiveQuotaToggleRow: View {
    let providerID: ProviderID
    let name: String
    let onChange: () -> Void
    @AppStorage private var enabled: Bool

    init(providerID: ProviderID, name: String, key: String, onChange: @escaping () -> Void) {
        self.providerID = providerID
        self.name = name
        self.onChange = onChange
        // The wrapped default only applies when nothing is registered for the key; the App
        // registers the on-by-default ones (Codex, Gemini) at launch.
        _enabled = AppStorage(wrappedValue: false, key)
    }

    var body: some View {
        Toggle(isOn: $enabled) {
            HStack(spacing: 10) {
                ProviderBrandMark.tinted(providerID, size: 18)
                Text(name)
                    .font(.sans(size: 13))
                    .foregroundColor(PadzyTheme.ink2)
            }
        }
        .toggleStyle(.padzy)
        .onChange(of: enabled) { onChange() }
        .help(ConnectionRow.liveDisclosure(for: providerID))
        .accessibilityLabel("Live quota for \(name)")
    }
}

/// Quota alerts: the existing master switch, the predictive "runs out before reset" warning
/// (`predictiveQuotaWarningsEnabled`) and per-provider thresholds
/// (`notificationThresholds.<providerID>`), all read by the notification engine.
struct QuotaAlertsSection: View {
    let providers: [ProviderID]
    let displayName: (ProviderID) -> String

    @AppStorage(NotificationEngine.notificationsEnabledKey) private var notificationsEnabled = true
    @AppStorage(AlertSettings.predictiveWarningsKey) private var predictiveEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: PadzySpace.m) {
            SectionLabel("Quota alerts")
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $notificationsEnabled) {
                    Text("Alert when a window crosses a threshold")
                        .font(.sans(size: 13))
                        .foregroundColor(PadzyTheme.ink2)
                }
                .toggleStyle(.padzy)
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $predictiveEnabled) {
                    Text("Warn before a window runs out")
                        .font(.sans(size: 13))
                        .foregroundColor(PadzyTheme.ink2)
                }
                .toggleStyle(.padzy)
                Text("Once per window, when it is on course to run out 15 minutes or more before its reset.")
                    .font(.sans(size: 11))
                    .foregroundColor(PadzyTheme.ink5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if notificationsEnabled && !providers.isEmpty {
                VStack(alignment: .leading, spacing: PadzySpace.s) {
                    Text("Thresholds, % used (up to four, blank for 80, 95)")
                        .font(.sans(size: 11))
                        .foregroundColor(PadzyTheme.ink5)
                    ForEach(providers, id: \.self) { id in
                        AlertThresholdRow(providerID: id, name: displayName(id))
                    }
                }
            }
        }
    }
}

/// One provider's thresholds as "80, 95": committed on Return or blur like the plan-cost
/// field; a value the engine cannot use reverts with a one-line hint instead of being saved.
private struct AlertThresholdRow: View {
    let providerID: ProviderID
    let name: String

    @State private var text = ""
    @State private var rejected = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 12) {
                ProviderBrandMark.tinted(providerID, size: 18)
                Text(name)
                    .font(.sans(size: 13))
                    .foregroundColor(PadzyTheme.ink2)
                    .lineLimit(1)
                Spacer(minLength: 8)
                TextField(AlertSettings.text(AlertSettings.defaultThresholds), text: $text)
                    .textFieldStyle(.plain)
                    .font(.mono(size: 12))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(PadzyTheme.ink)
                    .frame(width: 104)
                    .focused($isFocused)
                    .onSubmit { commit() }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                            .fill(PadzyTheme.statusBar)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                            .stroke(isFocused ? PadzyTheme.accent : PadzyTheme.border2, lineWidth: 1)
                    )
                    .accessibilityLabel("\(name) alert thresholds, percent used")
                Text("%")
                    .font(.mono(size: 12))
                    .foregroundColor(PadzyTheme.ink5)
            }
            if rejected {
                Text("Use whole numbers from 1 to 100, up to four.")
                    .font(.sans(size: 11))
                    .foregroundColor(PadzyTheme.ink3)
            }
        }
        .onAppear { text = storedText }
        .onChange(of: isFocused) { _, focused in if !focused { commit() } }
        .onDisappear { commit() }
    }

    /// Blank when the provider uses the default, so the placeholder shows it.
    private var storedText: String {
        let key = AlertSettings.thresholdsKey(for: providerID)
        guard UserDefaults.standard.object(forKey: key) != nil else { return "" }
        return AlertSettings.text(AlertSettings.thresholds(for: providerID))
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            AlertSettings.setThresholds(nil, for: providerID)
            rejected = false
            return
        }
        guard let values = AlertSettings.parse(trimmed) else {
            rejected = true
            text = storedText
            return
        }
        rejected = false
        text = AlertSettings.text(AlertSettings.setThresholds(values, for: providerID))
    }
}

/// Launch at login through `SMAppService.mainApp`. Its status is read back after every
/// change, so the row shows what macOS decided, including "needs approval".
struct LaunchAtLoginSection: View {
    @State private var status = SMAppService.mainApp.status
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PadzySpace.s) {
            SectionLabel("Startup")
            Toggle(isOn: Binding(get: { status == .enabled || status == .requiresApproval }, set: set)) {
                Text("Open Tokei at login")
                    .font(.sans(size: 13))
                    .foregroundColor(PadzyTheme.ink2)
            }
            .toggleStyle(.padzy)
            if status == .requiresApproval {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Needs approval in System Settings › General › Login Items.")
                        .font(.sans(size: 11))
                        .foregroundColor(PadzyTheme.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open") { SMAppService.openSystemSettingsLoginItems() }
                        .buttonStyle(.plain)
                        .font(.sans(size: 11, weight: .semibold))
                        .foregroundColor(PadzyTheme.ink)
                }
            }
            if let failure {
                Text(failure)
                    .font(.sans(size: 11))
                    .foregroundColor(PadzyTheme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { status = SMAppService.mainApp.status }
    }

    private func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            failure = nil
        } catch {
            failure = "macOS did not change it: \(error.localizedDescription). Nothing else was changed."
        }
        status = SMAppService.mainApp.status
    }
}

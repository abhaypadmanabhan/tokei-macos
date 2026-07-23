import SwiftUI
import Sparkle
import AIUsageDashboardCore

/// Shared chrome for the right-hand drawers (Settings, Add agent): a full-window
/// scrim (tap to dismiss) and a trailing panel with a titled header + a scrolling
/// body. Width is `min(380, 92%)` of the window; the panel carries a 1px left
/// border and elevates on `PadzyTheme.panel`.
///
/// The slide (panel) + fade (scrim) transition is declared here; the caller mounts
/// / unmounts the drawer inside a reduce-motion-gated animation, so this stays a
/// pure presentation container.
struct DrawerScaffold<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                // Scrim over the whole window — tap anywhere off the panel to dismiss.
                Rectangle()
                    .fill(PadzyTheme.scrim)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onClose() }
                    .transition(.opacity)
                    .accessibilityLabel("Dismiss")
                    .accessibilityAddTraits(.isButton)

                // Panel.
                VStack(spacing: 0) {
                    header
                    HairlineDivider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: PadzySpace.xxl) {
                            content()
                        }
                        .padding(.horizontal, PadzySpace.xl)
                        .padding(.vertical, 22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(width: min(380, geo.size.width * 0.92))
                .frame(maxHeight: .infinity)
                .background(PadzyTheme.panel)
                .overlay(alignment: .leading) {
                    Rectangle().fill(PadzyTheme.border2).frame(width: 1)
                }
                .transition(.move(edge: .trailing))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.sans(size: 15, weight: .semibold))
                .foregroundColor(PadzyTheme.ink)
            Spacer(minLength: 8)
            Button(action: onClose) {
                Text("\u{00D7}")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(PadzyTheme.ink4)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }
}

/// The Settings right-hand drawer (WP-5 IA consolidation). Every control here is
/// backed by a real store — plan cost, the notification flag, the menu-bar readout
/// mode, and the Sparkle updater. The prior drill-in `SettingsPane`'s "SOON"
/// placeholders (config presets, theme swatches, accent swatches, monthly limits,
/// channel pickers) are dropped rather than shipped inert.
struct SettingsDrawer: View {
    /// Closes the drawer (× / scrim / Escape all route here).
    let onClose: () -> Void
    /// Closes the drawer and switches the shell to the Agents tab.
    let onOpenAgents: () -> Void

    @EnvironmentObject private var viewModel: DashboardViewModel

    /// Gates the 80% / 95% quota notifications (`NotificationEngine.notificationsEnabledKey`).
    @AppStorage(NotificationEngine.notificationsEnabledKey) private var notificationsEnabled = true

    /// What the system menu-bar item renders — shared key with `MenuBarLabel`.
    @AppStorage(MenuBarDisplayMode.storageKey)
    private var menuBarModeRaw = MenuBarDisplayMode.todayTokens.rawValue

    private var menuBarMode: MenuBarDisplayMode {
        MenuBarDisplayMode(rawValue: menuBarModeRaw) ?? .todayTokens
    }

    /// Per-provider monthly plan price — the input the Value pane weighs against
    /// public API rates.
    private let planCosts = MaxxerPlanCostStore()

    /// Agents on the canvas (not signed out of the dashboard). Plan cost only makes
    /// sense for an agent you actually use; a removed/hidden agent is skipped.
    private var activeProviders: [ProviderID] {
        ProviderID.allCases.filter { AddAgentModel.isAdded($0) }
    }

    // Bundle version can't change at runtime — compute once.
    private static let appVersion: String =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"

    var body: some View {
        DrawerScaffold(title: "Settings", onClose: onClose) {
            planCostSection
            agentsDataSection
            appearanceSection
            notificationsSection
            feedbackSection
            versionSection
        }
    }

    private func displayName(_ id: ProviderID) -> String {
        viewModel.snapshot(for: id)?.displayName
            ?? id.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: 1 · Monthly plan cost

    private var planCostSection: some View {
        VStack(alignment: .leading, spacing: PadzySpace.m) {
            SectionLabel("Monthly plan cost")
            Text("Leave blank if an agent has no fixed plan.")
                .font(.sans(size: 11))
                .foregroundColor(PadzyTheme.ink5)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: PadzySpace.s) {
                ForEach(activeProviders, id: \.self) { id in
                    PlanCostDrawerRow(
                        providerID: id,
                        displayName: displayName(id),
                        store: planCosts,
                        detected: detectedPlan(for: id)
                    )
                }
            }
        }
    }

    /// Detection dispatch seam: one provider wired (Cursor, from its already-parsed
    /// plan label), the rest are `PlanDetector`'s research stubs (`nil` for now).
    private func detectedPlan(for id: ProviderID) -> DetectedPlan? {
        switch id {
        case .cursor:
            let planLabel = viewModel.snapshot(for: .cursor)?.quotaWindows.first?.label
            return PlanDetector.detectCursorPlan(planLabel: planLabel)
        default:
            return nil
        }
    }

    // MARK: 2 · Agents & data sources

    private var agentsDataSection: some View {
        VStack(alignment: .leading, spacing: PadzySpace.s) {
            SectionLabel("Agents & data sources")
            Text("Connect, hide, or reorder agents and see exactly which local file each one is read from.")
                .font(.sans(size: 11))
                .foregroundColor(PadzyTheme.ink4)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onOpenAgents) {
                Text("Agents tab \u{2192}")
                    .font(.sans(size: 12, weight: .medium))
                    .foregroundColor(PadzyTheme.accent)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open the Agents tab")
        }
    }

    // MARK: 3 · Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: PadzySpace.m) {
            SectionLabel("Appearance")

            HStack(spacing: 12) {
                Text("Theme")
                    .font(.sans(size: 13))
                    .foregroundColor(PadzyTheme.ink2)
                Spacer(minLength: 8)
                Text("Dark")
                    .font(.mono(size: 12))
                    .foregroundColor(PadzyTheme.ink3)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Menu bar shows")
                    .font(.sans(size: 13))
                    .foregroundColor(PadzyTheme.ink2)
                menuBarSegments
                Text(menuBarMode.hint)
                    .font(.sans(size: 11))
                    .foregroundColor(PadzyTheme.ink5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The real menu-bar readout control — a segmented picker over `MenuBarDisplayMode`,
    /// persisting to the key `MenuBarLabel` reads.
    private var menuBarSegments: some View {
        HStack(spacing: 0) {
            ForEach(Array(MenuBarDisplayMode.allCases.enumerated()), id: \.element.id) { index, mode in
                let isSelected = menuBarMode == mode
                Button {
                    menuBarModeRaw = mode.rawValue
                } label: {
                    Text(mode.title)
                        .font(.mono(size: 10))
                        .foregroundColor(isSelected ? PadzyTheme.ink : PadzyTheme.ink4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 4)
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
                        .fill(PadzyTheme.border2)
                        .frame(width: 1, height: 18)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                .stroke(PadzyTheme.border2, lineWidth: 1)
        )
    }

    // MARK: 4 · Notifications

    /// The single real notification flag (`NotificationEngine.notificationsEnabledKey`)
    /// gates the 80% / 95% quota alerts. It lives here, once — the mockup's separate
    /// "quota alerts" + "notifications" sections map to this one switch, so shipping
    /// two toggles for one flag would be an inert duplicate.
    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: PadzySpace.s) {
            SectionLabel("Notifications")
            Toggle(isOn: $notificationsEnabled) {
                Text("Quota alerts")
                    .font(.sans(size: 13))
                    .foregroundColor(PadzyTheme.ink2)
            }
            .toggleStyle(.padzy)
            Text("Notify when any window crosses 80% or 95%.")
                .font(.sans(size: 11))
                .foregroundColor(PadzyTheme.ink5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 5 · Feedback

    /// Feedback + diagnostics entry point. Not wired to a backend yet, so it reads
    /// as an honest "coming soon" rather than a dead button.
    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HairlineDivider()
            VStack(alignment: .leading, spacing: PadzySpace.m) {
                SectionLabel("Feedback")
                Text("Tell us what's working and what isn't, or send a diagnostic if something looks off.")
                    .font(.sans(size: 11))
                    .foregroundColor(PadzyTheme.ink5)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Text("Send feedback & diagnostics")
                        .font(.sans(size: 12, weight: .medium))
                        .foregroundColor(PadzyTheme.ink4)
                    Text("COMING SOON")
                        .font(.mono(size: 8.5))
                        .tracking(8.5 * 0.1)
                        .foregroundColor(PadzyTheme.ink5)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                                .stroke(PadzyTheme.border2, lineWidth: 1)
                        )
                    Spacer(minLength: 8)
                }
            }
            .padding(.top, PadzySpace.l)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Feedback and diagnostics, coming soon")
    }

    // MARK: 6 · Version

    private var versionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HairlineDivider()
            VStack(alignment: .leading, spacing: PadzySpace.m) {
                HStack(spacing: 12) {
                    Text("Version")
                        .font(.sans(size: 13))
                        .foregroundColor(PadzyTheme.ink2)
                    Spacer(minLength: 8)
                    Text(Self.appVersion)
                        .font(.mono(size: 12))
                        .foregroundColor(PadzyTheme.ink3)
                }

                HStack(spacing: 12) {
                    Button(action: { AppDelegate.shared?.checkForUpdates() }) {
                        Text("Check for updates")
                            .font(.sans(size: 12, weight: .medium))
                            .foregroundColor(canCheckForUpdates ? PadzyTheme.accent : PadzyTheme.ink5)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCheckForUpdates)
                    .accessibilityLabel("Check for updates")

                    Spacer(minLength: 8)

                    Text(updateStatusText)
                        .font(.mono(size: 10))
                        .foregroundColor(PadzyTheme.ink5)
                        .lineLimit(1)
                }
            }
            .padding(.top, PadzySpace.l)
        }
    }

    // MARK: Sparkle status (read-only, real updater state)

    private var canCheckForUpdates: Bool {
        AppDelegate.shared?.updater.updater.canCheckForUpdates ?? true
    }

    private var updateStatusText: String {
        guard let date = AppDelegate.shared?.updater.updater.lastUpdateCheckDate else {
            return "Not checked yet"
        }
        return "Checked \(Self.updateDateFormatter.string(from: date))"
    }

    private static let updateDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter
    }()
}

/// One agent's monthly plan price. Mono numerals in a `$`-prefixed, `/mo`-suffixed
/// field on `PadzyTheme.statusBar`; committed on blur/submit (never per keystroke).
/// Empty input clears the key — blank is "unset", distinct from "$0", and only
/// `nil` says the former, so the Value pane can tell them apart. Unparseable input
/// reverts to the stored value rather than writing garbage.
///
/// A preset menu (when the provider has a known catalog) prefills the field on
/// selection — an explicit pick commits immediately, same as typing. A `detected`
/// plan (best-effort, from `PlanDetector`) only ever prefills an *unset* field: the
/// row shows it badged and un-persisted until the user actually interacts with the
/// field (focuses it) — closing the drawer without touching it writes nothing, so
/// detection can never silently overwrite or fabricate a value (#51).
private struct PlanCostDrawerRow: View {
    let providerID: ProviderID
    let displayName: String
    let store: MaxxerPlanCostStore
    let detected: DetectedPlan?

    @State private var text: String = ""
    @State private var hasInteracted = false
    @FocusState private var isFocused: Bool

    private var presets: [PlanPreset] { PlanPresetCatalog.presets(for: providerID.rawValue) }

    /// `nil` once a value is saved — detection never overwrites it.
    private var suggestion: DetectedPlan? {
        PlanDetector.suggestedPlan(existingValue: store.monthlyUSD(for: providerID.rawValue), detected: detected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                ProviderBrandMark.tinted(providerID, size: 22)

                Text(displayName)
                    .font(.sans(size: 13))
                    .foregroundColor(PadzyTheme.ink2)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if !presets.isEmpty {
                    presetMenu
                }
                priceField
            }

            if let suggestion {
                detectedCaption(suggestion)
            }
        }
        .onAppear {
            text = Self.fieldText(store.monthlyUSD(for: providerID.rawValue) ?? suggestion?.monthlyUSD)
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                hasInteracted = true
            } else {
                commit()
            }
        }
        // The drawer can be torn down without a focus change firing.
        .onDisappear { commit() }
    }

    private var priceField: some View {
        HStack(spacing: 3) {
            Text("$")
                .font(.mono(size: 11))
                .foregroundColor(text.isEmpty ? PadzyTheme.ink5 : PadzyTheme.ink2)
            TextField("unset", text: $text)
                .textFieldStyle(.plain)
                .font(.mono(size: 11))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundColor(PadzyTheme.ink)
                .frame(width: 50)
                .focused($isFocused)
                .onSubmit { commit() }
                .accessibilityLabel("\(displayName) monthly plan cost in US dollars")
            Text("/mo")
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.ink5)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                .fill(PadzyTheme.statusBar)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                .stroke(isFocused ? PadzyTheme.accent : PadzyTheme.border2, lineWidth: 1)
        )
    }

    /// Known-plan picker — a plain chip menu, not a text hint, so it stays legible
    /// in the drawer's tight width. Selecting an entry is an explicit user action
    /// (like typing a price) and commits immediately.
    private var presetMenu: some View {
        Menu {
            ForEach(presets) { preset in
                Button("\(preset.label) · $\(Self.fieldText(preset.monthlyUSD))/mo") {
                    applyPreset(preset.monthlyUSD)
                }
            }
        } label: {
            Text("PRESET")
                .font(.mono(size: 8.5))
                .tracking(8.5 * 0.08)
                .foregroundColor(PadzyTheme.ink4)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                        .stroke(PadzyTheme.border2, lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("\(displayName) plan presets")
    }

    /// Subtle disclosure for an un-persisted detected suggestion — never a second
    /// accent hue, just a bordered mono kicker plus its source.
    private func detectedCaption(_ plan: DetectedPlan) -> some View {
        HStack(spacing: 6) {
            Text("DETECTED")
                .font(.mono(size: 8.5))
                .tracking(8.5 * 0.08)
                .foregroundColor(PadzyTheme.ink5)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .overlay(
                    RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                        .stroke(PadzyTheme.border2, lineWidth: 1)
                )
            Text("from \(plan.source) — edit or leave as-is to confirm")
                .font(.sans(size: 10))
                .foregroundColor(PadzyTheme.ink5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 34)
        .accessibilityElement(children: .combine)
    }

    private func applyPreset(_ amount: Double) {
        hasInteracted = true
        text = Self.fieldText(amount)
        store.setMonthlyUSD(amount, for: providerID.rawValue)
    }

    private func commit() {
        // An un-persisted detected suggestion the user never touched: leave it
        // alone rather than writing it on a stray blur/teardown.
        guard hasInteracted || suggestion == nil else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            store.setMonthlyUSD(nil, for: providerID.rawValue)
            text = ""
            return
        }

        let cleaned = trimmed
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")

        guard let value = Double(cleaned), value.isFinite, value >= 0 else {
            text = Self.fieldText(store.monthlyUSD(for: providerID.rawValue))
            return
        }

        store.setMonthlyUSD(value, for: providerID.rawValue)
        text = Self.fieldText(value)
    }

    /// Plain two-decimal text — no grouping separators, so it survives being read
    /// straight back by `commit()`.
    private static func fieldText(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", value)
    }
}

// MARK: - Previews

@MainActor
private func mockVM(_ ids: [ProviderID]) -> DashboardViewModel {
    let vm = DashboardViewModel()
    vm.snapshots = ids.map {
        ProviderSnapshot(providerID: $0,
                         displayName: $0.rawValue.replacingOccurrences(of: "_", with: " ").capitalized,
                         authStatus: .authenticated, quotaWindows: [],
                         todayUsage: .unavailable, weekUsage: .unavailable, warnings: [])
    }
    return vm
}

#Preview("Settings drawer") {
    ZStack {
        PadzyTheme.ground.ignoresSafeArea()
        SettingsDrawer(onClose: {}, onOpenAgents: {})
            .environmentObject(mockVM(ProviderID.allCases))
    }
    .frame(width: 900, height: 700)
    .preferredColorScheme(.dark)
}

import SwiftUI
import AIUsageDashboardCore

/// The "+  link a coding agent" sheet. Two honest regions:
///   DETECTED  — providers whose install marker exists on disk but that the user
///               hasn't added yet: one-click ADD, plus ADD ALL DETECTED.
///   ALL AGENTS — every provider with its logo, addable even when undetected, and
///               removable (= hidden) when already on the canvas.
///
/// "Add" just un-hides the provider (`AddAgentModel`) and re-runs the sync so a
/// freshly-added agent starts fetching immediately. All detection is disk-only.
struct AddAgentSheet: View {
    @EnvironmentObject private var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    /// Bumped on every add/remove so the DETECTED / ADDED partitions recompute.
    @State private var version = 0

    private var detected: [ProviderID] {
        _ = version
        return AddAgentModel.detectedNotAdded()
    }

    private func displayName(_ id: ProviderID) -> String {
        viewModel.snapshot(for: id)?.displayName
            ?? id.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            HairlineDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !detected.isEmpty {
                        detectedSection
                    }
                    allAgentsSection
                }
                .padding(24)
            }
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 420, idealHeight: 560)
        .background(PadzyTheme.ground)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ADD AGENT")
                    .font(.display(size: 20, weight: .black))
                    .foregroundColor(PadzyTheme.ink)
                Text("Link a coding agent to track its usage. Local-first — detection reads only paths on disk.")
                    .font(.mono(size: 11))
                    .foregroundColor(PadzyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PadzyTheme.muted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(24)
    }

    // MARK: Detected

    private var detectedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel("Detected on this Mac", size: 11)
                Button(action: addAllDetected) {
                    Text("ADD ALL")
                        .font(.mono(size: 11))
                        .foregroundColor(PadzyTheme.ground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(PadzyTheme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add all detected agents")
            }

            VStack(spacing: 0) {
                ForEach(detected, id: \.self) { id in
                    agentRow(id, detected: true)
                    HairlineDivider()
                }
            }
            .overlay(Rectangle().stroke(PadzyTheme.muted.opacity(0.3), lineWidth: 1))
        }
    }

    // MARK: All agents (manual)

    private var allAgentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("All agents", size: 11)
            VStack(spacing: 0) {
                ForEach(ProviderID.allCases, id: \.self) { id in
                    agentRow(id, detected: AgentDetection.isInstalled(id))
                    if id != ProviderID.allCases.last { HairlineDivider() }
                }
            }
            .overlay(Rectangle().stroke(PadzyTheme.muted.opacity(0.3), lineWidth: 1))
        }
    }

    // MARK: Row

    private func agentRow(_ id: ProviderID, detected: Bool) -> some View {
        let added = AddAgentModel.isAdded(id)
        return HStack(spacing: 14) {
            ProviderMark(id, size: 22, enabled: added || detected)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName(id))
                    .font(.display(size: 14, weight: .bold))
                    .foregroundColor(PadzyTheme.ink)
                    .lineLimit(1)
                Text(detected ? "DETECTED" : "NOT DETECTED")
                    .font(.mono(size: 10))
                    .tracking(0.5)
                    .foregroundColor(PadzyTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if added {
                Button(action: { remove(id) }) {
                    Text("ADDED ✓")
                        .font(.mono(size: 11))
                        .foregroundColor(PadzyTheme.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .overlay(Rectangle().stroke(PadzyTheme.muted.opacity(0.5), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove from dashboard")
                .accessibilityLabel("Remove \(displayName(id))")
            } else {
                Button(action: { add(id) }) {
                    Text("ADD")
                        .font(.mono(size: 11))
                        .foregroundColor(PadzyTheme.ground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(PadzyTheme.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(displayName(id))")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Mutations

    private func add(_ id: ProviderID) {
        AddAgentModel.add(id)
        version += 1
        Task { await viewModel.refresh() }
    }

    private func remove(_ id: ProviderID) {
        AddAgentModel.remove(id)
        version += 1
    }

    private func addAllDetected() {
        for id in detected { AddAgentModel.add(id) }
        version += 1
        Task { await viewModel.refresh() }
    }
}

/// The `+` affordance itself — a square, hairline-bounded button. One shared look
/// for the Overview header and the sidebar.
struct AddAgentButton: View {
    var compact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: compact ? 11 : 12, weight: .bold))
                if !compact {
                    Text("ADD AGENT")
                        .font(.mono(size: 11))
                }
            }
            .foregroundColor(PadzyTheme.accent)
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 6 : 7)
            .overlay(Rectangle().stroke(PadzyTheme.accent, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a coding agent")
    }
}

// MARK: - Previews

@MainActor
private func mockVM(_ ids: [ProviderID]) -> DashboardViewModel {
    let vm = DashboardViewModel()
    vm.snapshots = ids.map {
        ProviderSnapshot(providerID: $0, displayName: $0.rawValue.capitalized,
                         authStatus: .authenticated, quotaWindows: [],
                         todayUsage: .unavailable, weekUsage: .unavailable, warnings: [])
    }
    return vm
}

#Preview("Add Agent sheet") {
    AddAgentSheet()
        .environmentObject(mockVM([.claudeCode, .cursor, .codex]))
}

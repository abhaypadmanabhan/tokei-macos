import SwiftUI
import AIUsageDashboardCore

/// The "Add agent" right-hand drawer (WP-5 IA consolidation) — replaces the modal
/// `AddAgentSheet`. Two honest lists, both driven by `AddAgentModel`:
///   DETECTED ON THIS MAC · N — providers whose install marker exists on disk but
///                              that aren't on the canvas yet (`detectedNotAdded`).
///   ALL AGENTS               — every provider, addable even when undetected.
///
/// "Add" un-hides the provider and re-runs the sync so it starts fetching at once;
/// "Connected" reflects an added agent and removes it on tap. All detection is
/// disk-only (`AgentDetection`), never a provider call.
struct AddAgentDrawer: View {
    let onClose: () -> Void

    @EnvironmentObject private var viewModel: DashboardViewModel

    /// Bumped on every add/remove so the DETECTED / ALL partitions recompute.
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
        DrawerScaffold(title: "Add agent", onClose: onClose) {
            if !detected.isEmpty {
                detectedSection
            }
            allAgentsSection
        }
    }

    // MARK: Detected

    private var detectedSection: some View {
        VStack(alignment: .leading, spacing: PadzySpace.s) {
            HStack(spacing: 8) {
                Circle()
                    .fill(PadzyTheme.good)
                    .frame(width: 6, height: 6)
                Text("Detected on this Mac \u{00B7} \(detected.count)")
                    .font(.mono(size: 10))
                    .tracking(10 * 0.14)
                    .foregroundColor(PadzyTheme.ink5)
            }
            VStack(spacing: PadzySpace.s) {
                ForEach(detected, id: \.self) { id in
                    agentRow(id)
                }
            }
        }
    }

    // MARK: All agents

    private var allAgentsSection: some View {
        VStack(alignment: .leading, spacing: PadzySpace.s) {
            SectionLabel("All agents")
            VStack(spacing: PadzySpace.s) {
                ForEach(ProviderID.allCases, id: \.self) { id in
                    agentRow(id)
                }
            }
        }
    }

    // MARK: Row

    private func agentRow(_ id: ProviderID) -> some View {
        let added = AddAgentModel.isAdded(id)
        let path = ProviderMetadata.localPaths(for: id).first ?? "\u{2014}"

        return HStack(spacing: 12) {
            ProviderBrandMark.tinted(id, size: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(id))
                    .font(.sans(size: 13))
                    .foregroundColor(PadzyTheme.ink)
                    .lineLimit(1)
                Text(path)
                    .font(.mono(size: 10))
                    .foregroundColor(PadzyTheme.ink5)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if added {
                Button(action: { remove(id) }) {
                    Text("Connected")
                        .font(.mono(size: 11))
                        .foregroundColor(PadzyTheme.ink4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                                .stroke(PadzyTheme.border2, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove from dashboard")
                .accessibilityLabel("Remove \(displayName(id))")
            } else {
                Button(action: { add(id) }) {
                    Text("Add")
                        .font(.mono(size: 11))
                        .foregroundColor(PadzyTheme.ground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                                .fill(PadzyTheme.accent)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(displayName(id))")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: PadzyRadius.cell, style: .continuous)
                .fill(PadzyTheme.window)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PadzyRadius.cell, style: .continuous)
                .stroke(PadzyTheme.hairline, lineWidth: 1)
        )
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
}

/// The `+` affordance — a square, hairline-bounded button. One shared look for the
/// blank-canvas call to action, the Connections header, and (compact) the chip
/// strip's trailing `+`. (Relocated here from the retired `AddAgentSheet`.)
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

#Preview("Add agent drawer") {
    ZStack {
        PadzyTheme.ground.ignoresSafeArea()
        AddAgentDrawer(onClose: {})
            .environmentObject(mockVM([.claudeCode, .cursor, .codex]))
    }
    .frame(width: 900, height: 700)
    .preferredColorScheme(.dark)
}

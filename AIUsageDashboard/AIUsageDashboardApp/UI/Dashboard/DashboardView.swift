import SwiftUI
import AIUsageDashboardCore

struct DashboardView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pulseOpacity: Double = 1.0

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var isClaudeInstalled: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudeDir = home.appendingPathComponent(".claude", isDirectory: true)
        return FileManager.default.fileExists(atPath: claudeDir.path)
    }

    /// Daily totals sorted by day, most recent last, limited to the trailing `days`.
    private func dailySeries(days: Int?) -> [Int] {
        guard let totals = viewModel.claudeSnapshot?.dailyTotals, !totals.isEmpty else { return [] }
        let sorted = totals.sorted { $0.key < $1.key }.map(\.value)
        if let days, sorted.count > days { return Array(sorted.suffix(days)) }
        return sorted
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Rectangle()
                    .fill(PadzyTheme.muted.opacity(0.3))
                    .frame(width: 1)
                if isClaudeInstalled {
                    usagePane
                } else {
                    emptyState
                }
            }
            statusStrip
        }
        .background(PadzyTheme.ground)
        .frame(minWidth: 860, minHeight: 560)
        .task {
            viewModel.beginAutoSync()
            await viewModel.refresh()
        }
    }

    // MARK: 01 / PROVIDERS

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialKicker(number: "01", title: "PROVIDERS")
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)
            HairlineDivider()

            providerRow(name: "CLAUDE CODE", selected: true, available: true)
            HairlineDivider()
            ForEach(ProviderID.allCases.filter { $0 != .claudeCode }, id: \.self) { providerID in
                providerRow(
                    name: providerID.rawValue.replacingOccurrences(of: "_", with: " ").uppercased(),
                    selected: false,
                    available: false
                )
                HairlineDivider()
            }
            Spacer()
        }
        .frame(width: 230)
    }

    private func providerRow(name: String, selected: Bool, available: Bool) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(selected ? PadzyTheme.accent : Color.clear)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.display(size: 15, weight: selected ? .black : .bold))
                    .foregroundColor(available ? PadzyTheme.ink : PadzyTheme.muted)
                if !available {
                    Text("UNAVAILABLE")
                        .font(.mono(size: 9))
                        .foregroundColor(PadzyTheme.muted.opacity(0.7))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            Spacer()
        }
        .background(selected ? PadzyTheme.surface : Color.clear)
        .accessibilityElement(children: .combine)
    }

    // MARK: 02 / USAGE

    private var usagePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                EditorialKicker(number: "02", title: "USAGE")
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 8) {
                Text("01 / TODAY")
                    .font(.mono(size: 12))
                    .tracking(12 * 0.04)
                    .foregroundColor(PadzyTheme.muted)

                Text(TokenFormatter.format(viewModel.claudeSnapshot?.todayUsage.totalTokens))
                    .font(.display(size: 150, weight: .black))
                    .foregroundColor(PadzyTheme.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.25)
                    .frame(maxWidth: .infinity, alignment: .leading)

                usageBreakdown
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)

            Spacer(minLength: 16)
            HairlineDivider()

            HStack(alignment: .top, spacing: 0) {
                metricBlock(number: "02", title: "7D ROLLING",
                            usage: viewModel.claudeSnapshot?.weekUsage, series: dailySeries(days: 7))
                verticalHairline
                metricBlock(number: "03", title: "30D ROLLING",
                            usage: viewModel.claudeSnapshot?.monthUsage, series: dailySeries(days: 30))
                verticalHairline
                metricBlock(number: "04", title: "LIFETIME",
                            usage: viewModel.claudeSnapshot?.lifetimeUsage, series: dailySeries(days: nil))
            }
            .frame(height: 168)
        }
    }

    private var usageBreakdown: some View {
        HStack(spacing: 24) {
            breakdownItem("INPUT", viewModel.claudeSnapshot?.todayUsage.inputTokens)
            breakdownItem("OUTPUT", viewModel.claudeSnapshot?.todayUsage.outputTokens)
            breakdownItem("CACHE READ", viewModel.claudeSnapshot?.todayUsage.cacheReadTokens)
            breakdownItem("CACHE WRITE", viewModel.claudeSnapshot?.todayUsage.cacheCreationTokens)
            if let confidence = viewModel.claudeSnapshot?.todayUsage.confidence {
                ConfidenceBadge(confidence: confidence)
            }
        }
    }

    private func breakdownItem(_ label: String, _ value: Int?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.muted)
            Text(TokenFormatter.format(value))
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.ink)
        }
    }

    private var verticalHairline: some View {
        Rectangle()
            .fill(PadzyTheme.muted.opacity(0.3))
            .frame(width: 1)
    }

    private func metricBlock(number: String, title: String, usage: TokenUsage?, series: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(number) / \(title)")
                .font(.mono(size: 11))
                .tracking(11 * 0.04)
                .foregroundColor(PadzyTheme.muted)
            Text(TokenFormatter.format(usage?.totalTokens))
                .font(.display(size: 40, weight: .black))
                .foregroundColor(PadzyTheme.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Sparkline(values: series)
                .frame(height: 44)
                .accessibilityHidden(true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 03 / STATUS

    private var statusStrip: some View {
        VStack(spacing: 0) {
            if let warnings = viewModel.claudeSnapshot?.warnings.filter({ $0.level != .info }), !warnings.isEmpty {
                HairlineDivider()
                HStack(spacing: 8) {
                    Text("!!")
                        .font(.mono(size: 10))
                        .foregroundColor(PadzyTheme.accent)
                    Text(warnings.map(\.message).joined(separator: "  ·  ").uppercased())
                        .font(.mono(size: 10))
                        .foregroundColor(PadzyTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            HairlineDivider()
            HStack(spacing: 16) {
                Text("03 / STATUS")
                    .font(.mono(size: 11))
                    .tracking(11 * 0.04)
                    .foregroundColor(PadzyTheme.muted)

                if viewModel.isLoading {
                    Rectangle()
                        .fill(PadzyTheme.accent)
                        .frame(width: 6, height: 6)
                        .opacity(pulseOpacity)
                        .onAppear {
                            if !reduceMotion {
                                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                                    pulseOpacity = 0.2
                                }
                            }
                        }
                }

                Text(statusLine)
                    .font(.mono(size: 12))
                    .foregroundColor(PadzyTheme.ink)
                    .lineLimit(1)

                Spacer()

                Button(action: { Task { await viewModel.refresh() } }) {
                    Text("SYNC NOW")
                        .font(.mono(size: 12))
                        .foregroundColor(PadzyTheme.ground)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(PadzyTheme.accent)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(viewModel.isLoading)
                .accessibilityLabel("Sync now")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var statusLine: String {
        let synced = viewModel.lastSyncedAt.map { Self.timeFormatter.string(from: $0) } ?? "NEVER"
        let confidence = viewModel.claudeSnapshot?.todayUsage.confidence.displayName.uppercased() ?? "—"
        return "SYNCED \(synced)  ·  \(confidence)  ·  WATCHING ~/.claude"
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            EditorialKicker(number: "02", title: "USAGE")
            Text("NO CLAUDE CODE DIRECTORY DETECTED")
                .font(.display(size: 18, weight: .black))
                .foregroundColor(PadzyTheme.ink)
            Text("Expected location: ~/.claude")
                .font(.mono(size: 12))
                .foregroundColor(PadzyTheme.ink)
            Text("Install Claude Code and run it once in your terminal to initialize session logs.")
                .font(.system(size: 12))
                .foregroundColor(PadzyTheme.muted)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

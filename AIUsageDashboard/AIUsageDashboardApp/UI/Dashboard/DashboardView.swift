import SwiftUI
import AIUsageDashboardCore

struct DashboardView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var pulseOpacity: Double = 1.0
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
    
    private var isClaudeInstalled: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudeDir = home.appendingPathComponent(".claude", isDirectory: true)
        return FileManager.default.fileExists(atPath: claudeDir.path)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar (01 / PROVIDERS)
            VStack(alignment: .leading, spacing: 16) {
                EditorialKicker(number: "01", title: "PROVIDERS")
                
                VStack(spacing: 1) {
                    // Claude Code: Available and Selected
                    let claudeToday = viewModel.claudeSnapshot?.todayUsage
                    ProviderCard(
                        providerID: .claudeCode,
                        displayName: "CLAUDE CODE",
                        todayUsage: claudeToday,
                        isSelected: true,
                        isAvailable: true
                    )
                    
                    HairlineDivider()
                    
                    // Other providers are unavailable
                    ForEach(ProviderID.allCases.filter { $0 != .claudeCode }, id: \.self) { providerID in
                        ProviderCard(
                            providerID: providerID,
                            displayName: providerID.rawValue.replacingOccurrences(of: "_", with: " "),
                            todayUsage: nil,
                            isSelected: false,
                            isAvailable: false
                        )
                        HairlineDivider()
                    }
                }
                
                Spacer()
            }
            .frame(width: 220)
            .padding(.top, 20)
            .padding(.horizontal, 16)
            
            // Exposed Hairline Divider
            Rectangle()
                .fill(PadzyTheme.muted.opacity(0.3))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            
            // Detail Area (02 / USAGE)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !isClaudeInstalled {
                        // Empty/error state: no ~/.claude directory
                        VStack(alignment: .leading, spacing: 16) {
                            EditorialKicker(number: "02", title: "USAGE")
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Text("NO CLAUDE CODE DIRECTORY DETECTED")
                                    .font(.display(size: 14, weight: .bold))
                                    .foregroundColor(PadzyTheme.accent)
                                
                                Text("Expected location: ~/.claude")
                                    .font(.mono(size: 11))
                                    .foregroundColor(PadzyTheme.ink)
                                
                                Text("Please make sure Claude Code is installed and has been run at least once in your terminal to initialize session logs.")
                                    .font(.system(size: 12))
                                    .foregroundColor(PadzyTheme.muted)
                                    .lineLimit(nil)
                            }
                            .padding(16)
                            .background(PadzyTheme.surface)
                            .border(PadzyTheme.accent.opacity(0.4), width: 1)
                        }
                    } else {
                        // Regular detail view
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 4) {
                                EditorialKicker(number: "02", title: "USAGE")
                                
                                Text("CLAUDE CODE")
                                    .font(.display(size: 24, weight: .black))
                                    .foregroundColor(PadzyTheme.ink)
                            }
                            
                            Spacer()
                            
                            // Sync status bar
                            HStack(spacing: 12) {
                                // Sync indicator (accent tick that pulses when loading)
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
                                } else {
                                    // Solid static tick on bottom edge of status or just omitted when idle
                                    Rectangle()
                                        .fill(PadzyTheme.muted)
                                        .frame(width: 6, height: 6)
                                }
                                
                                // Last synced timestamp
                                if let date = viewModel.lastSyncedAt {
                                    Text("SYNCED: \(timeFormatter.string(from: date))")
                                        .font(.mono(size: 10))
                                        .foregroundColor(PadzyTheme.muted)
                                } else {
                                    Text("SYNCED: NEVER")
                                        .font(.mono(size: 10))
                                        .foregroundColor(PadzyTheme.muted)
                                }
                                
                                // Refresh Button (CMD+R shortcut)
                                Button(action: {
                                    Task {
                                        await viewModel.refresh()
                                    }
                                }) {
                                    Text("REFRESH")
                                        .font(.mono(size: 10))
                                        .foregroundColor(PadzyTheme.accent)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.clear)
                                        .border(PadzyTheme.accent, width: 1)
                                }
                                .buttonStyle(.plain)
                                .keyboardShortcut("r", modifiers: .command)
                                .disabled(viewModel.isLoading)
                            }
                            .padding(.bottom, 4)
                        }
                        
                        // 2x2 grid of rolling window metrics
                        let snapshot = viewModel.claudeSnapshot
                        let columns = [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ]
                        
                        LazyVGrid(columns: columns, spacing: 12) {
                            MetricBlock(title: "TODAY", usage: snapshot?.todayUsage)
                            MetricBlock(title: "7D ROLLING", usage: snapshot?.weekUsage)
                            MetricBlock(title: "30D ROLLING", usage: snapshot?.monthUsage)
                            MetricBlock(title: "LIFETIME", usage: snapshot?.lifetimeUsage)
                        }
                        
                        // Warnings section if any exist
                        if let warnings = snapshot?.warnings, !warnings.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                EditorialKicker(number: "03", title: "WARNINGS")
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(warnings) { warning in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("!!")
                                                .font(.mono(size: 10))
                                                .foregroundColor(PadzyTheme.accent)
                                            Text(warning.message.uppercased())
                                                .font(.mono(size: 10))
                                                .foregroundColor(PadzyTheme.muted)
                                                .lineLimit(nil)
                                        }
                                    }
                                }
                                .padding(12)
                                .background(PadzyTheme.surface)
                                .border(PadzyTheme.muted.opacity(0.3), width: 1)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(PadzyTheme.ground)
        .frame(minWidth: 760, minHeight: 480)
        .task {
            viewModel.beginAutoSync()
            await viewModel.refresh()
        }
    }
}

private struct MetricBlock: View {
    let title: String
    let usage: TokenUsage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.display(size: 11, weight: .bold))
                    .foregroundColor(PadzyTheme.muted)

                Spacer()

                if let usage = usage {
                    ConfidenceBadge(confidence: usage.confidence)
                }
            }

            Text(TokenFormatter.format(usage?.totalTokens))
                .font(.mono(size: 24))
                .foregroundColor(PadzyTheme.ink)

            VStack(alignment: .leading, spacing: 4) {
                MetricRow(label: "INPUT", value: usage?.inputTokens)
                MetricRow(label: "OUTPUT", value: usage?.outputTokens)
                MetricRow(label: "CACHE READ", value: usage?.cacheReadTokens)
                MetricRow(label: "CACHE WRITE", value: usage?.cacheCreationTokens)
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(PadzyTheme.surface)
        .border(PadzyTheme.muted.opacity(0.3), width: 1)
    }
}

private struct MetricRow: View {
    let label: String
    let value: Int?

    var body: some View {
        HStack {
            Text(label)
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.muted)
            Spacer()
            Text(TokenFormatter.format(value))
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.ink)
        }
    }
}

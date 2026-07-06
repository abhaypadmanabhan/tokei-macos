import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("GENERAL", systemImage: "slider.horizontal.3")
                }
            
            AboutSettingsTab()
                .tabItem {
                    Label("ABOUT", systemImage: "info.circle")
                }
        }
        .padding(20)
        .frame(width: 420, height: 260)
        .background(PadzyTheme.ground)
    }
}

private struct GeneralSettingsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EditorialKicker(number: "01", title: "REFRESH INTERVAL")
            
            VStack(alignment: .leading, spacing: 8) {
                Text("AUTO-SYNC: FILE WATCHER")
                    .font(.display(size: 12, weight: .bold))
                    .foregroundColor(PadzyTheme.ink)
                
                Text("WATCHING ~/.claude/projects  ·  2S DEBOUNCE")
                    .font(.mono(size: 11))
                    .foregroundColor(PadzyTheme.muted)
                
                Text("Tokei refreshes automatically whenever Claude Code writes new session logs. Manual sync: \u{2318}R in the dashboard.")
                    .font(.system(size: 11))
                    .foregroundColor(PadzyTheme.muted)
                    .lineLimit(nil)
            }
            .padding(12)
            .background(PadzyTheme.surface)
            .border(PadzyTheme.muted.opacity(0.3), width: 1)
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

private struct AboutSettingsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EditorialKicker(number: "02", title: "METADATA")
            
            VStack(alignment: .leading, spacing: 6) {
                Text("TOKEI")
                    .font(.display(size: 16, weight: .black))
                    .foregroundColor(PadzyTheme.ink)
                
                Text("AI USAGE TELEMETRY  ·  VERSION 0.1.0")
                    .font(.mono(size: 11))
                    .foregroundColor(PadzyTheme.accent)
                
                HairlineDivider()
                    .padding(.vertical, 4)
                
                Text("Designed under Padzy OS design system constraints (cool dark, signal pink).")
                    .font(.system(size: 11))
                    .foregroundColor(PadzyTheme.muted)
            }
            .padding(12)
            .background(PadzyTheme.surface)
            .border(PadzyTheme.muted.opacity(0.3), width: 1)
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

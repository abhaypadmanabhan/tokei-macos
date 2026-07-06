import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Text("General settings placeholder")
                .tabItem { Label("General", systemImage: "gear") }
            Text("Providers settings placeholder")
                .tabItem { Label("Providers", systemImage: "externaldrive") }
            Text("Notifications settings placeholder")
                .tabItem { Label("Notifications", systemImage: "bell") }
        }
        .padding()
        .frame(width: 480, height: 320)
    }
}

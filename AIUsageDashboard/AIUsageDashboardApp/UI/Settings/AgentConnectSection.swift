import SwiftUI
import AIUsageDashboardCore

/// Care detail: each row keeps its button in place while the client responds; the
/// result is read back from that client, with one recovery action on failure.
@MainActor
struct AgentConnectSection: View {
    @State private var states: [AgentConnectionState] = []
    @State private var busy: AgentClient?
    @State private var working = false
    @State private var message: String?

    private var connection: AgentConnection {
        AgentConnection(helper: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/tokei"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PadzySpace.m) {
            SectionHeading("Connect agents")
            Text("Let your agents read usage and use plan capacity before it resets.")
                .font(.sans(size: 12))
                .foregroundColor(PadzyTheme.ink3)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: PadzySpace.m) {
                ForEach(AgentClient.allCases) { client in
                    clientRow(client)
                }
            }
            Button("Install the tokei command") { installCommand() }
                .buttonStyle(.plain)
                .font(.sans(size: 12, weight: .medium))
                .foregroundColor(PadzyTheme.ink)
                .disabled(working)
                .help("Adds the bundled command to ~/.local/bin")
            if let feedback {
                Text(feedback)
                    .font(.sans(size: 12))
                    .foregroundColor(PadzyTheme.ink3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await refresh() }
    }

    private func clientRow(_ client: AgentClient) -> some View {
        let state = states.first { $0.client == client }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(client.name).font(.sans(size: 13)).foregroundColor(PadzyTheme.ink2)
                Text(busy == client ? "Updating…" : status(state))
                    .font(.sans(size: 12)).foregroundColor(PadzyTheme.ink3)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(state?.connected == true ? "Disconnect" : "Connect") {
                change(client, install: state?.connected != true)
            }
            .buttonStyle(.plain)
            .font(.sans(size: 12, weight: .medium))
            .foregroundColor(PadzyTheme.ink)
            .frame(width: 76, alignment: .trailing)
            .disabled(working || state == nil || state?.detected == false || state?.message != nil)
            .accessibilityLabel("\(state?.connected == true ? "Disconnect" : "Connect") \(client.name)")
            .help(state?.detected == false ? "Install \(client.name), then reopen Settings." : "Share Tokei's read-only usage snapshot")
        }
    }

    private var feedback: String? { message ?? states.compactMap(\.message).first }

    private func status(_ state: AgentConnectionState?) -> String {
        guard let state else { return "Checking…" }
        if state.message != nil { return "Needs attention" }
        return state.connected ? "Connected" : state.detected ? "Detected" : "Not found; install the client first"
    }

    private func refresh() async {
        let service = connection
        states = await Task.detached(priority: .userInitiated) {
            AgentClient.allCases.map { service.state(for: $0) }
        }.value
    }

    private func change(_ client: AgentClient, install: Bool) {
        working = true
        busy = client
        let service = connection
        Task {
            message = await Task.detached(priority: .userInitiated) {
                do { return try service.change(client, install: install) }
                catch { return error.localizedDescription }
            }.value
            await refresh()
            busy = nil
            working = false
        }
    }

    private func installCommand() {
        working = true
        let service = connection
        Task {
            message = await Task.detached(priority: .userInitiated) {
                do { return try service.installCommand(includePATHHint: false) }
                catch { return error.localizedDescription }
            }.value
            working = false
        }
    }
}

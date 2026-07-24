import Foundation

/// Detects local GitHub Copilot installations without reading or copying credentials.
///
/// Copilot's supported clients keep authentication in OS-protected secret storage, and
/// the VS Code extension obtains quota snapshots from authenticated network responses.
/// No stable, documented local token-usage or quota record is currently available, so
/// snapshots deliberately report unavailable metrics instead of inferring a schema.
public actor CopilotProvider: UsageProvider {
    public let id: ProviderID = .copilot
    public let displayName: String = "GitHub Copilot"

    /// No data capability is advertised until Copilot exposes a stable source that
    /// Tokei can consume without accessing credentials.
    public nonisolated var capabilities: ProviderCapabilities { [] }

    private let fileManager: FileManager
    private let installationMarkers: [URL]
    private let extensionDirectories: [URL]

    public init(
        fileManager: FileManager = .default,
        installationMarkers: [URL]? = nil,
        extensionDirectories: [URL]? = nil
    ) {
        self.fileManager = fileManager

        let home = fileManager.homeDirectoryForCurrentUser
        self.installationMarkers = installationMarkers ?? [
            home.appendingPathComponent(".copilot", isDirectory: true),
            home.appendingPathComponent(".config/github-copilot", isDirectory: true),
            home.appendingPathComponent(".local/bin/copilot"),
            URL(fileURLWithPath: "/opt/homebrew/bin/copilot"),
            URL(fileURLWithPath: "/usr/local/bin/copilot"),
            home.appendingPathComponent(
                "Library/Application Support/Code/User/globalStorage/github.copilot-chat",
                isDirectory: true
            ),
            home.appendingPathComponent(
                "Library/Application Support/Code/User/globalStorage/github.copilot",
                isDirectory: true
            ),
            URL(fileURLWithPath: "/Applications/GitHub Copilot for Xcode.app", isDirectory: true),
        ]
        self.extensionDirectories = extensionDirectories ?? [
            home.appendingPathComponent(".vscode/extensions", isDirectory: true),
            home.appendingPathComponent(".vscode-insiders/extensions", isDirectory: true),
            home.appendingPathComponent(".cursor/extensions", isDirectory: true),
        ]
    }

    public func detectAvailability() async -> ProviderAvailability {
        if installationMarkers.contains(where: { fileManager.fileExists(atPath: $0.path) }) {
            return .installed
        }

        for directory in extensionDirectories {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            if entries.contains(where: Self.isCopilotExtension) {
                return .installed
            }
        }

        return .notInstalled
    }

    public func authenticate() async throws -> AuthStatus {
        await detectAvailability() == .installed ? .unknown : .unauthenticated
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        let availability = await detectAvailability()
        let isInstalled = availability == .installed
        let warning = isInstalled
            ? ProviderWarning(
                message: "GitHub Copilot usage is unavailable because Copilot doesn't persist a documented local usage or quota record that Tokei can safely read.",
                level: .info
            )
            : ProviderWarning(
                message: "GitHub Copilot is not installed on this Mac.",
                level: .info
            )

        return ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: isInstalled ? .unknown : .unauthenticated,
            quotaWindows: [],
            todayUsage: .unavailable,
            weekUsage: .unavailable,
            monthUsage: .unavailable,
            lifetimeUsage: .unavailable,
            costUsage: nil,
            warnings: [warning],
            lastSyncedAt: nil
        )
    }

    private nonisolated static func isCopilotExtension(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name == "github.copilot"
            || name.hasPrefix("github.copilot-")
            || name == "github.copilot-chat"
            || name.hasPrefix("github.copilot-chat-")
    }
}

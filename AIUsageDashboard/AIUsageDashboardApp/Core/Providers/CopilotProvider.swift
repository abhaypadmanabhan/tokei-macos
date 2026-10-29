import Foundation

/// Reads Copilot CLI shutdown usage from session-state without accessing credentials.
/// Extension-only installs remain visible with unavailable metrics until CLI logs exist.
public actor CopilotProvider: UsageProvider {
    public let id: ProviderID = .copilot
    public let displayName: String = "GitHub Copilot"

    public nonisolated var capabilities: ProviderCapabilities { [.localLog] }

    private let sessionParser: CopilotSessionParser
    private let fileManager: FileManager
    private var calendar: Calendar
    private let now: @Sendable () -> Date
    private let installationMarkers: [URL]
    private let extensionDirectories: [URL]

    /// Install status doesn't flip mid-session — compute once instead of re-stat'ing
    /// up to 8 marker paths plus scanning 3 extension directories on every sync cycle.
    private var cachedAvailability: ProviderAvailability?

    public init(
        fileManager: FileManager = .default,
        installationMarkers: [URL]? = nil,
        extensionDirectories: [URL]? = nil,
        sessionParser: CopilotSessionParser = .init(),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.now = now
        self.sessionParser = sessionParser

        let home = fileManager.homeDirectoryForCurrentUser
        // Copilot has no single canonical install location (VS Code extension, Cursor's
        // bundled VS Code, Xcode plugin, standalone CLI). The VS Code globalStorage and
        // Xcode-app paths are verified against real local installs; the standalone-CLI
        // paths (~/.copilot, ~/.config/github-copilot, and the bin/copilot locations) are
        // best-effort guesses at where a future/less-common CLI install might land — a
        // wrong guess here just means "not detected," never a false positive.
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
            URL(fileURLWithPath: "/Applications/GitHub Copilot for Xcode.app", isDirectory: true)
        ]
        self.extensionDirectories = extensionDirectories ?? [
            home.appendingPathComponent(".vscode/extensions", isDirectory: true),
            home.appendingPathComponent(".vscode-insiders/extensions", isDirectory: true),
            home.appendingPathComponent(".cursor/extensions", isDirectory: true)
        ]
    }

    public func detectAvailability() async -> ProviderAvailability {
        if let cachedAvailability { return cachedAvailability }

        let availability = scanForInstallation()
        cachedAvailability = availability
        return availability
    }

    private func scanForInstallation() -> ProviderAvailability {
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

    public func updateCalendar(_ calendar: Calendar) async {
        self.calendar = calendar
        await sessionParser.updateCalendar(calendar)
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        let fetchedAt = now()
        let history = await sessionParser.parse()
        let availability = await detectAvailability()
        let isInstalled = availability == .installed || history.shutdownCount > 0
        let warning = isInstalled
            ? ProviderWarning(
                message: "GitHub Copilot CLI usage appears after a session ends. No local CLI usage has been recorded.",
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
            todayUsage: history.today,
            weekUsage: history.week,
            monthUsage: history.month,
            lifetimeUsage: history.lifetime,
            costUsage: costUsage(history, at: fetchedAt),
            warnings: history.warnings + (history.shutdownCount == 0 ? [warning] : []),
            lastSyncedAt: history.shutdownCount == 0 ? nil : fetchedAt,
            dailyTotals: history.dailyTotals,
            dailyModelUsage: history.lifetime.totalTokens == nil ? nil : history.dailyModelUsage
        )
    }

    private func costUsage(_ history: CopilotSessionParser.AggregateUsage, at reference: Date) -> CostUsage? {
        let pricing = PricingEngine(table: PricingService.cachedTable())
        let month = calendar.dateInterval(of: .month, for: reference)
        let models = UsageAggregation.sumModels(history.dailyModelUsage.compactMap { day, models in
            guard let month, day >= month.start, day <= reference else { return nil }
            return models
        })
        let amounts = models.compactMap { pricing.cost(model: $0.key, tokens: $0.value) }
        guard !amounts.isEmpty else { return nil }
        return CostUsage(amount: amounts.reduce(0, +), currency: "USD", confidence: .estimated)
    }

    private nonisolated static func isCopilotExtension(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name == "github.copilot" || name.hasPrefix("github.copilot-")
    }
}

extension CopilotProvider: CalendarAwareProvider {}

import Foundation

/// Reads Copilot CLI shutdown usage from session-state without accessing credentials.
/// Extension-only installs remain visible with unavailable metrics until CLI logs exist.
///
/// Live billing is opt-in: only with `copilotLiveBillingEnabled` on AND a GitHub token saved
/// in Settings (Tokei's own Keychain) does it ask GitHub's official billing API for the
/// person's own premium-request and AI-credit usage this month.
public actor CopilotProvider: UsageProvider {
    public let id: ProviderID = .copilot
    public let displayName: String = "GitHub Copilot"

    public nonisolated var capabilities: ProviderCapabilities {
        userDefaultsReader.bool(forKey: OfficialSignIn.githubBilling.liveEnabledKey)
            ? [.localLog, .cost, .providerEndpoint]
            : [.localLog]
    }

    private let sessionParser: CopilotSessionParser
    private let fileManager: FileManager
    private var calendar: Calendar
    private let now: @Sendable () -> Date
    private let installationMarkers: [URL]
    private let extensionDirectories: [URL]
    private let billingClient: any CopilotBillingFetching
    private let secretStore: any SecretStore
    private nonisolated let userDefaultsReader: ProviderUserDefaultsReader

    /// Install status doesn't flip mid-session — compute once instead of re-stat'ing
    /// up to 8 marker paths plus scanning 3 extension directories on every sync cycle.
    private var cachedAvailability: ProviderAvailability?

    public init(
        fileManager: FileManager = .default,
        installationMarkers: [URL]? = nil,
        extensionDirectories: [URL]? = nil,
        sessionParser: CopilotSessionParser = .init(),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init,
        billingClient: (any CopilotBillingFetching)? = nil,
        secretStore: (any SecretStore)? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.fileManager = fileManager
        self.billingClient = billingClient ?? CopilotBillingClient()
        self.secretStore = secretStore ?? Keychain.shared
        self.userDefaultsReader = ProviderUserDefaultsReader(userDefaults)
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

        let billing = await liveBilling(at: fetchedAt)
        let hasLocalUsage = history.shutdownCount > 0

        return ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: billing.authenticated ? .authenticated : (isInstalled ? .unknown : .unauthenticated),
            quotaWindows: billing.windows,
            todayUsage: history.today,
            weekUsage: history.week,
            monthUsage: history.month,
            lifetimeUsage: history.lifetime,
            // GitHub's billed amount, when it answered, is the real cost; else the local estimate.
            costUsage: billing.cost ?? costUsage(history, at: fetchedAt),
            warnings: history.warnings + (hasLocalUsage || billing.authenticated ? [] : [warning]) + billing.warnings,
            lastSyncedAt: hasLocalUsage || billing.authenticated ? fetchedAt : nil,
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

    // MARK: - GitHub billing (official, opt-in)

    private struct LiveBilling {
        var windows: [QuotaWindow] = []
        var cost: CostUsage?
        var warnings: [ProviderWarning] = []
        var authenticated = false
    }

    private func liveBilling(at fetchedAt: Date) async -> LiveBilling {
        let signIn = OfficialSignIn.githubBilling
        guard userDefaultsReader.bool(forKey: signIn.liveEnabledKey) else { return LiveBilling() }
        do {
            guard let token = try await secretStore.secret(for: signIn.keychainAccount) else {
                throw OfficialUsageError.missingCredential
            }
            let usage = try await billingClient.fetchUsage(token: token)
            var result = LiveBilling(
                windows: CopilotBillingParser.quotaWindows(from: usage, observedAt: fetchedAt),
                cost: CopilotBillingParser.billedCost(from: usage),
                authenticated: true
            )
            if usage.isEmpty {
                result.warnings.append(ProviderWarning(
                    message: "\(signIn.warningPrefix) GitHub shows no personal Copilot usage this month."
                        + " A seat paid for by an organization or enterprise is not in personal billing;"
                        + " that needs an org admin's billing access, not this token.",
                    level: .info
                ))
            }
            return result
        } catch {
            return LiveBilling(warnings: [Self.billingWarning(for: error)])
        }
    }

    static func billingWarning(for error: Error) -> ProviderWarning {
        let prefix = OfficialSignIn.githubBilling.warningPrefix
        switch error {
        case OfficialUsageError.missingCredential:
            return ProviderWarning(
                message: "\(prefix) live billing is on but no GitHub token is saved."
                    + " Paste one in Settings › Live quota.",
                level: .info
            )
        case OfficialUsageError.unauthorized:
            return ProviderWarning(
                message: "\(prefix) GitHub rejected the saved token (401): it is wrong, revoked or expired."
                    + " Make a new one.",
                level: .warning
            )
        case OfficialUsageError.forbidden:
            return ProviderWarning(
                message: "\(prefix) GitHub refused billing access (403). Either the token lacks the"
                    + " Plan: Read permission, or your Copilot seat is managed by an organization or"
                    + " enterprise. Those seats need an org admin's billing access; a personal token"
                    + " cannot read them.",
                level: .warning
            )
        case OfficialUsageError.cooldownActive, OfficialUsageError.rateLimited:
            return ProviderWarning(
                message: "\(prefix) GitHub rate limited the request, will retry later.", level: .info
            )
        case is KeychainError:
            return ProviderWarning(
                message: "\(prefix) could not read the saved token from the Keychain.", level: .warning
            )
        default:
            return ProviderWarning(
                message: "\(prefix) could not read billing right now (\(error.localizedDescription)).",
                level: .warning
            )
        }
    }

    private nonisolated static func isCopilotExtension(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name == "github.copilot" || name.hasPrefix("github.copilot-")
    }
}

extension CopilotProvider: CalendarAwareProvider {}

import Foundation

public actor AntigravityProvider: UsageProvider {
    public let id: ProviderID = .antigravity
    public let displayName: String = "Antigravity"
    public let capabilities: ProviderCapabilities = [.localLog, .quota]

    private let fileManager: FileManager
    private let stateDatabaseURL: URL
    private let parser: AntigravityStateDBParser

    public init(
        fileManager: FileManager = .default,
        stateDatabaseURL: URL? = nil,
        parser: AntigravityStateDBParser = .init()
    ) {
        self.fileManager = fileManager
        self.stateDatabaseURL = stateDatabaseURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Antigravity/User/globalStorage/state.vscdb")
        self.parser = parser
    }

    public func detectAvailability() async -> ProviderAvailability {
        fileManager.fileExists(atPath: stateDatabaseURL.path) ? .installed : .notInstalled
    }

    public func authenticate() async throws -> AuthStatus {
        fileManager.fileExists(atPath: stateDatabaseURL.path) ? .authenticated : .unknown
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        let state = await parser.parse(stateDatabaseURL: stateDatabaseURL)

        return ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: try await authenticate(),
            quotaWindows: quotaWindows(from: state),
            todayUsage: .unavailable,
            weekUsage: .unavailable,
            monthUsage: nil,
            lifetimeUsage: nil,
            costUsage: nil,
            warnings: warnings(from: state),
            lastSyncedAt: Date()
        )
    }

    private func quotaWindows(from state: AntigravityStateDBParser.ParsedState) -> [QuotaWindow] {
        guard let availableCredits = state.availableCredits else {
            return []
        }

        let minimumCreditAmount = state.minimumCreditAmountForUsage
        let limit = minimumCreditAmount.map { availableCredits + $0 }
        let used = limit.map { $0 - availableCredits }

        return [
            QuotaWindow(
                providerID: id,
                type: .credits,
                used: used.map(Double.init),
                limit: limit.map(Double.init),
                remaining: Double(availableCredits),
                resetAt: nil,
                confidence: .localParsed,
                source: "antigravity local protobuf"
            )
        ]
    }

    private func warnings(from state: AntigravityStateDBParser.ParsedState) -> [ProviderWarning] {
        var warnings = state.warnings

        if let planName = state.planName, !planName.isEmpty {
            warnings.append(ProviderWarning(message: "Plan: \(planName)", level: .info))
        }

        for fieldNumber in state.rawQuotaValues.keys.sorted() {
            guard let value = state.rawQuotaValues[fieldNumber] else { continue }
            warnings.append(ProviderWarning(
                message: "Antigravity raw quota field \(fieldNumber): \(value)",
                level: .info
            ))
        }

        return warnings
    }
}

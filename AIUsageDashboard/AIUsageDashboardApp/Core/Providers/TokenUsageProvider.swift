import Foundation

public protocol TokenUsageProvider: Sendable {
    func fetchTokenUsage(range: UsageRange) async throws -> TokenUsage
}

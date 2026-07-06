import Foundation

public struct DailyUsage: Sendable, Codable {
    public let date: Date
    public let providerID: ProviderID
    public let tokenUsage: TokenUsage

    public init(date: Date, providerID: ProviderID, tokenUsage: TokenUsage) {
        self.date = date
        self.providerID = providerID
        self.tokenUsage = tokenUsage
    }
}

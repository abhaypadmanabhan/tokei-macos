import Foundation

public struct ProviderCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let localLog = ProviderCapabilities(rawValue: 1 << 0)
    public static let quota = ProviderCapabilities(rawValue: 1 << 1)
    public static let tokenUsage = ProviderCapabilities(rawValue: 1 << 2)
    public static let providerEndpoint = ProviderCapabilities(rawValue: 1 << 3)
    public static let cost = ProviderCapabilities(rawValue: 1 << 4)
}

import Foundation

public struct ProviderWarning: Sendable, Identifiable {
    public let id = UUID()
    public let message: String
    public let level: Level

    public enum Level: String, Sendable {
        case info
        case warning
        case error
    }

    public init(message: String, level: Level = .warning) {
        self.message = message
        self.level = level
    }
}


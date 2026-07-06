import Foundation

public protocol LocalLogProvider: Sendable {
    func discoverLogSources() async throws -> [LogSource]
}

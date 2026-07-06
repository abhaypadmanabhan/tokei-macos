import Foundation

public protocol QuotaProvider: Sendable {
    func fetchQuotaWindows() async throws -> [QuotaWindow]
}

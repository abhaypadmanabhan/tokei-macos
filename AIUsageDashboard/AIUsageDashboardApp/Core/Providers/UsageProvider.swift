import Foundation

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    var capabilities: ProviderCapabilities { get }
    func detectAvailability() async -> ProviderAvailability
    func authenticate() async throws -> AuthStatus
    func fetchSnapshot() async throws -> ProviderSnapshot
}

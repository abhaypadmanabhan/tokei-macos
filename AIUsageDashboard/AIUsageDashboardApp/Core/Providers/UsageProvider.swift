import Foundation

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    var capabilities: ProviderCapabilities { get }
    func detectAvailability() async -> ProviderAvailability
    func authenticate() async throws -> AuthStatus
    func fetchSnapshot() async throws -> ProviderSnapshot
}

/// Providers whose cached day buckets depend on the effective calendar (D9). Kept as a
/// separate protocol so `UsageProvider` stays frozen; the sync engine forwards timezone
/// changes to whichever providers adopt it.
public protocol CalendarAwareProvider: Sendable {
    func updateCalendar(_ calendar: Calendar) async
}

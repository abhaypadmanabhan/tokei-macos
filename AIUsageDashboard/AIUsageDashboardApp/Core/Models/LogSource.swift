import Foundation

public struct LogSource: Sendable {
    public let providerID: ProviderID
    public let url: URL
    public let sessionID: String?
    public let lastModified: Date?

    public init(providerID: ProviderID, url: URL, sessionID: String? = nil, lastModified: Date? = nil) {
        self.providerID = providerID
        self.url = url
        self.sessionID = sessionID
        self.lastModified = lastModified
    }
}

import Foundation

public struct LogSource: Sendable {
    public let providerID: ProviderID
    public let url: URL
    public let sessionID: String?
    public let lastModified: Date?
    /// Size captured during discovery, so a warm parser pass does not stat the file again.
    public let fileSize: UInt64?

    public init(
        providerID: ProviderID,
        url: URL,
        sessionID: String? = nil,
        lastModified: Date? = nil,
        fileSize: UInt64? = nil
    ) {
        self.providerID = providerID
        self.url = url
        self.sessionID = sessionID
        self.lastModified = lastModified
        self.fileSize = fileSize
    }
}

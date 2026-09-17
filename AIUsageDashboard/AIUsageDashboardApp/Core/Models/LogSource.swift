import Foundation

public struct LogSource: Sendable {
    public let providerID: ProviderID
    public let url: URL
    public let sessionID: String?
    public let lastModified: Date?
    /// Size captured during discovery, so a warm parser pass does not stat the file again.
    public let fileSize: UInt64?
    /// Filesystem identity captured during discovery, so equal-size replacements cannot
    /// masquerade as unchanged files on the zero-stat cache path.
    public let fileIdentifier: Data?

    public init(
        providerID: ProviderID,
        url: URL,
        sessionID: String? = nil,
        lastModified: Date? = nil,
        fileSize: UInt64? = nil,
        fileIdentifier: Data? = nil
    ) {
        self.providerID = providerID
        self.url = url
        self.sessionID = sessionID
        self.lastModified = lastModified
        self.fileSize = fileSize
        self.fileIdentifier = fileIdentifier
    }
}

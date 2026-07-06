import Foundation

public enum MetricConfidence: String, CaseIterable, Sendable {
    case exact
    case providerReported
    case localParsed
    case estimated
    case unavailable

    public var displayName: String {
        switch self {
        case .exact: return "Exact"
        case .providerReported: return "Provider Reported"
        case .localParsed: return "Local Parsed"
        case .estimated: return "Estimated"
        case .unavailable: return "Unavailable"
        }
    }
}

import Foundation

public enum AuthStatus: String, Sendable {
    case authenticated
    case unauthenticated
    case unknown
    case error
}

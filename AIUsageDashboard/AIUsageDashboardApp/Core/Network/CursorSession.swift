import Foundation
import CryptoKit

/// Assembles the WorkOS session cookie Cursor's web dashboard endpoints require.
///
/// The cookie is `WorkosCursorSessionToken=<userId>%3A%3A<jwt>` — the `::`
/// separator is URL-encoded, matching the Cursor CLI. `userId` is derived from
/// the JWT's `sub` claim and normalized the same way the CLI normalizes it.
///
/// SECURITY: nothing here is logged or persisted. The JWT and the assembled
/// cookie leave the process only as the `Cookie` header over TLS
/// (`CursorUsageClientImpl`). Decoding reads only the `sub` claim — never the
/// signature, never the raw token into any log line.
enum CursorSession {
    /// The full cookie value, or `nil` when a `userId` cannot be derived. Returning
    /// `nil` (no request) is deliberately preferred over sending a malformed cookie
    /// that Cursor would reject.
    static func cookie(jwt: String) -> String? {
        guard let userID = userID(fromJWT: jwt) else { return nil }
        return "WorkosCursorSessionToken=\(userID)%3A%3A\(jwt)"
    }

    /// The normalized WorkOS user id from a JWT's `sub` claim, or `nil` if the token
    /// is malformed or the subject isn't a shape Cursor recognizes.
    static func userID(fromJWT jwt: String) -> String? {
        let segments = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2,
              let payloadData = decodeBase64URL(String(segments[1])),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let subject = json["sub"] as? String else {
            return nil
        }
        return normalizeSubject(subject)
    }

    /// Mirrors the Cursor CLI's `normalizeCursorSubject`:
    /// - a subject ending in `|user_XXXX` (any provider prefix) → just `user_XXXX`
    /// - a subject matching `^(google-oauth2|github|oidc|auth0)\|<id>$` → verbatim
    /// - anything else → `nil`
    static func normalizeSubject(_ subject: String) -> String? {
        if let barIndex = subject.lastIndex(of: "|") {
            let tail = String(subject[subject.index(after: barIndex)...])
            if !tail.isEmpty,
               tail.range(of: #"^user_[A-Za-z0-9_]+$"#, options: .regularExpression) != nil {
                return tail
            }
        }
        if subject.range(of: #"^(google-oauth2|github|oidc|auth0)\|[^|]+$"#, options: .regularExpression) != nil {
            return subject
        }
        return nil
    }

    /// Stable, non-reversible identifier for a cookie. Used as a filename suffix
    /// so per-account cooldown files don't collide and the raw cookie never appears
    /// on disk. SHA-256 truncated to 128 bits (32 hex chars) gives ample collision
    /// resistance for this local file-keying purpose.
    static func identityHash(for cookie: String) -> String {
        SHA256.hash(data: Data(cookie.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func decodeBase64URL(_ segment: String) -> Data? {
        var base64 = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        return Data(base64Encoded: base64)
    }
}

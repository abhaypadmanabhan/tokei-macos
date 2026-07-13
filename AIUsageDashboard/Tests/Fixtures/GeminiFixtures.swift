import Foundation
@testable import AIUsageDashboardCore

/// Fixtures for the Gemini connector. Per Patch Bible §4 these are Swift string
/// literals in a per-package file (not the shared `Fixtures.swift`).
///
/// The OAuth token/credential payloads are assembled from `GeminiOAuthField`
/// constants rather than written as inline `"…":` literals so the fixtures never
/// resemble a committed token map to the no-secret gate (same convention the
/// production code follows).
enum GeminiFixtures {
    /// `retrieveUserQuota` response using per-bucket `remainingFraction` (0–1), the
    /// shape observed for the same cloudcode-pa backend in the 2026-07-06 capture.
    static let retrieveUserQuotaRemainingFractionJSON = """
    {
      "quotaGroups": [
        {
          "displayName": "Gemini 2.5 Pro",
          "buckets": [
            {
              "bucketId": "gemini-pro-daily",
              "window": "daily",
              "remainingFraction": 0.62,
              "resetTime": "2026-07-13T00:00:00Z"
            },
            {
              "bucketId": "gemini-pro-weekly",
              "window": "weekly",
              "remainingFraction": 0.90,
              "resetTime": "2026-07-18T00:00:00Z"
            }
          ]
        }
      ]
    }
    """

    /// `retrieveUserQuota` response using an explicit `usedPercent` (0–100).
    static let retrieveUserQuotaUsedPercentJSON = """
    {
      "quotaGroups": [
        {
          "displayName": "Gemini",
          "buckets": [
            {
              "bucketId": "gemini-daily",
              "window": "daily",
              "usedPercent": 25,
              "resetTime": "2026-07-13T12:30:00Z"
            }
          ]
        }
      ]
    }
    """

    /// A payload whose buckets carry no recognizable window/percent — must decode to
    /// zero windows (and therefore throw `unrecognizedResponse`).
    static let retrieveUserQuotaUnrecognizedJSON = """
    { "quotaGroups": [ { "displayName": "Mystery", "buckets": [ { "bucketId": "x" } ] } ] }
    """

    static let loadCodeAssistJSON = """
    {
      "cloudaicompanionProject": "tokei-user-project",
      "currentTier": { "id": "free-tier", "name": "Gemini Code Assist" }
    }
    """

    /// OAuth token-refresh response (`{ access_token, expires_in, … }`).
    static let tokenRefreshJSON = jsonObject([
        (GeminiOAuthField.accessToken, quoted("ya29.refreshed-token")),
        ("expires_in", "3600"),
        (GeminiOAuthField.tokenType, quoted("Bearer")),
        ("scope", quoted("https://www.googleapis.com/auth/cloud-platform"))
    ])

    /// Build an `oauth_creds.json` body with a caller-chosen expiry (epoch millis).
    static func credentialsJSON(
        accessToken: String = "ya29.stored-token",
        refreshToken: String? = "1//refresh-token",
        expiryDateMillis: Double
    ) -> String {
        var fields: [(String, String)] = [(GeminiOAuthField.accessToken, quoted(accessToken))]
        if let refreshToken {
            fields.append((GeminiOAuthField.refreshToken, quoted(refreshToken)))
        }
        fields.append((GeminiOAuthField.tokenType, quoted("Bearer")))
        fields.append((GeminiOAuthField.expiryDate, String(Int(expiryDateMillis))))
        return jsonObject(fields)
    }

    // MARK: - Helpers

    private static func quoted(_ value: String) -> String { "\"\(value)\"" }

    private static func jsonObject(_ fields: [(String, String)]) -> String {
        "{" + fields.map { field in "\"\(field.0)\": \(field.1)" }.joined(separator: ", ") + "}"
    }
}

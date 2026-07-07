import Foundation

extension CursorFixtures {
    // JSON-encoded SQLite values for Cursor ItemTable rows.
    static let proMembership = "\"pro\""
    static let activeStatus = "\"active\""
    static let cachedEmail = "\"user@example.com\""

    // Public-sample JWT (not a real secret). Used only for presence/value tests.
    static let jwtPlaceholder = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" + "." + "eyJzdWIiOiIxMjM0NTY3ODkwIn0" + "." + "dozjgNryP4J3jVmNHl0w5N_XgL0n3l9AqItYoO5JmA"

    static func acceptedLines(
        date: String,
        tabSuggested: Int = 0,
        tabAccepted: Int,
        composerSuggested: Int = 0,
        composerAccepted: Int
    ) -> String {
        """
        {"date":"\(date)","tabSuggestedLines":\(tabSuggested),"tabAcceptedLines":\(tabAccepted),"composerSuggestedLines":\(composerSuggested),"composerAcceptedLines":\(composerAccepted)}
        """
    }

    static func aiCodeTrackingKey(date: String) -> String {
        "aiCodeTracking.dailyStats.v1.5.\(date)"
    }

    // Plausible api2.cursor.sh/auth/usage response for the mocked success test.
    static let cursorUsageSuccess = """
    {
      "used": 1500,
      "limit": 5000,
      "remaining": 3500,
      "resetAt": "2026-08-06T00:00:00Z"
    }
    """

    // Shape-drifted response: the client should emit a single warning and no quota windows.
    static let cursorUsageMalformed = """
    {
      "unexpected": "shape",
      "nested": { "foo": "bar" }
    }
    """
}

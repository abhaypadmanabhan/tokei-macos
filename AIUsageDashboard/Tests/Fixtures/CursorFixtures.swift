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

    // Real api2.cursor.sh/auth/usage shape (verified 2026-07-06): per-model
    // request/token usage keyed by model name, plus billing-cycle start. This model
    // carries a request cap, so the decoder emits a monthly percent gauge.
    static let cursorUsageSuccess = """
    {
      "gpt-4": {
        "numRequests": 150,
        "numRequestsTotal": 150,
        "numTokens": 1000,
        "maxTokenUsage": null,
        "maxRequestUsage": 500
      },
      "startOfMonth": "2026-06-11T08:06:30.000Z"
    }
    """

    // Shape-drifted response: the client should emit a single warning and no quota windows.
    static let cursorUsageMalformed = """
    {
      "unexpected": "shape",
      "nested": { "foo": "bar" }
    }
    """

    static let cursorStripeProfileSuccess = """
    {"membershipType":"pro","subscriptionStatus":"active","individualMembershipType":"pro",
     "isYearlyPlan":false,"isOnBillableAuto":true,"customerBalance":null,"isTeamMember":false,
     "teamMembershipType":null,"trialEligible":false,"trialLengthDays":7,"verifiedStudent":false,
     "lastPaymentFailed":false,"pendingCancellationDate":null,"paymentRecoveryAction":null}
    """
}

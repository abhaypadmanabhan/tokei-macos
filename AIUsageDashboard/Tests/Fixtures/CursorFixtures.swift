import Foundation

extension CursorFixtures {
    // JSON-encoded SQLite values for Cursor ItemTable rows.
    static let proMembership = "\"pro\""
    static let activeStatus = "\"active\""
    static let cachedEmail = "\"user@example.com\""

    /// A JWT whose `sub` normalizes to a WorkOS user id (`auth0|user_01TEST` →
    /// `user_01TEST`), so `CursorSession` can assemble a cookie. Not a real secret —
    /// the signature segment is a placeholder.
    static let jwtPlaceholder = jwt(sub: "auth0|user_01TEST")

    /// Builds a syntactically valid, unsigned JWT carrying the given `sub`.
    static func jwt(sub: String) -> String {
        let header = base64URL(#"{"alg":"HS256","typ":"JWT"}"#)
        let payload = base64URL("{\"sub\":\"\(sub)\"}")
        return "\(header).\(payload).signature"
    }

    private static func base64URL(_ string: String) -> String {
        Data(string.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

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

    // MARK: - cursor.com/api/dashboard/export-usage-events-csv?strategy=tokens

    /// Header-then-rows export. Columns are looked up by name, and Cursor inserts
    /// extra columns over time (here `Cloud Agent ID`, `Automation ID`, `Kind`,
    /// `Max Mode`) — the parser must ignore position and unknown columns.
    /// Token math per row: cacheWrite = Input(w/ Cache Write) − Input(w/o).
    static let usageEventsCSV = """
    Date,Cloud Agent ID,Automation ID,Kind,Model,Max Mode,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens,Total Tokens,Cost
    2026-07-08T09:00:00.000Z,,,Included,claude-opus-4-8,No,1200,1000,500,300,2000,$0.05
    2026-07-04T10:30:00.000Z,,,On-Demand,claude-sonnet-5,Yes,600,500,100,200,900,"$1,234.56"
    2026-06-20T12:00:00.000Z,agent-1,,Included,gpt-5,No,400,400,0,100,500,$0.01
    2026-07-08T23:59:59.999Z,,,"Errored, No Charge",claude-opus-4-8,No,0,0,0,0,0,$0.00
    """

    /// An export with none of the required columns → parser yields zero events.
    static let usageEventsCSVMissingColumns = """
    Date,Model,Something Else
    2026-07-08T09:00:00.000Z,claude-opus-4-8,42
    """

    // MARK: - cursor.com/api/usage-summary

    /// Plan carries `totalPercentUsed` (the preferred headline) + a billing cycle end.
    static let usageSummary = """
    {
      "membershipType": "pro",
      "limitType": "individual",
      "billingCycleEnd": "2026-07-31T00:00:00.000Z",
      "individualUsage": {
        "plan": {
          "totalPercentUsed": 42.5,
          "autoPercentUsed": 40,
          "apiPercentUsed": 45,
          "used": 4250,
          "limit": 10000
        },
        "onDemand": { "used": 0, "limit": 5000 }
      }
    }
    """

    /// Plan with no percent fields but cents `used`/`limit` → percent = used/limit*100.
    static let usageSummaryCentsOnly = """
    {
      "membershipType": "pro",
      "billingCycleEnd": "2026-07-31T00:00:00.000Z",
      "individualUsage": { "plan": { "used": 3000, "limit": 12000 } }
    }
    """

    /// No individual plan usage at all → decoder returns nil percent (no fake gauge).
    static let usageSummaryEmpty = """
    { "membershipType": "free", "individualUsage": { "plan": {} } }
    """
}

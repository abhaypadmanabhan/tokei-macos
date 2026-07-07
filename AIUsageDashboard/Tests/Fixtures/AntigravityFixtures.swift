enum AntigravityFixtures {
    static let userStatusProtoBase64 = "ahoKGBIDUHJvOICAAUDYBGDQhgNo8JMJcKjDAQ=="
    static let modelCreditsProtoBase64 = "CiUKG2F2YWlsYWJsZUNyZWRpdHNTZW50aW5lbEtleRIGCgRFT2dICigKHm1pbmltdW1DcmVkaXRBbW91bnRGb3JVc2FnZUtleRIGCgRFREk9"
    static let miniReaderNestedPayloadHex = "089601"
    static let miniReaderMixedWireHex = "0a030896019806071d4433221121080706050403020112026f6b2eff"
    static let malformedUnknownWireHex = "08012eff"

    static let quotaSummaryJSON = """
    { "response": {
      "groups": [
        { "displayName": "Gemini Models",
          "description": "Models within this group: Gemini Flash, Gemini Pro",
          "buckets": [
            { "bucketId": "gemini-weekly", "displayName": "Weekly Limit",
              "description": "You have used some of your weekly limit, it will fully refresh in 4 days, 12 hours.",
              "window": "weekly", "remainingFraction": 0.9150608, "resetTime": "2026-07-11T18:48:56Z" },
            { "bucketId": "gemini-5h", "displayName": "Five Hour Limit",
              "description": "You have used some of your 5-hour limit, it will fully refresh in 4 hours, 30 minutes.",
              "window": "5h", "remainingFraction": 0.8757648, "resetTime": "2026-07-07T10:45:03Z" } ] },
        { "displayName": "Claude and GPT models",
          "description": "Models within this group: Claude Opus, Claude Sonnet, GPT-OSS",
          "buckets": [
            { "bucketId": "3p-weekly", "displayName": "Weekly Limit", "window": "weekly",
              "remainingFraction": 1, "resetTime": "2026-07-14T06:14:13Z" },
            { "bucketId": "3p-5h", "displayName": "Five Hour Limit", "window": "5h",
              "remainingFraction": 1, "resetTime": "2026-07-07T11:14:13Z" } ] } ],
      "description": "Within each group, models share a weekly limit and a 5-hour limit. Quota is consumed proportionally to the cost of the tokens..."
    } }
    """
}

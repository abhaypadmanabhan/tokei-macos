import Foundation

enum ClaudeFixtures {
  static let assistantLine = """
    {"parentUuid":"parent-1","isSidechain":false,"userType":"external","cwd":"/path","sessionId":"8f83c022-session","version":"2.1.201","gitBranch":"HEAD","message":{"model":"claude-fable-5","id":"msg_01TmqABC","type":"message","role":"assistant","content":[],"stop_reason":"tool_use","usage":{"input_tokens":4,"cache_creation_input_tokens":24924,"cache_read_input_tokens":14085,"output_tokens":250,"service_tier":"standard"}},"requestId":"req_011CckXYZ","type":"assistant","uuid":"79741816-line","timestamp":"2026-07-06T07:55:59.226Z"}
    """

  static let duplicateAssistantBlocks = """
    {"message":{"id":"msg_dup","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":20,"cache_creation_input_tokens":10}},"requestId":"req_dup","type":"assistant","uuid":"uuid-1","timestamp":"2026-07-06T10:00:00.000Z"}
    {"message":{"id":"msg_dup","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":20,"cache_creation_input_tokens":10}},"requestId":"req_dup","type":"assistant","uuid":"uuid-2","timestamp":"2026-07-06T10:00:00.000Z"}
    """

  static let userLine = """
    {"type":"user","uuid":"user-uuid-1","timestamp":"2026-07-06T07:55:00.000Z","message":{"role":"user","content":[{"type":"text","text":"hello"}]}}
    """

  static let summaryLine = """
    {"type":"summary","summary":"Session summary text","leafUuid":"leaf-1","timestamp":"2026-07-06T08:00:00.000Z"}
    """

  static let sidechainLine = """
    {"isSidechain":true,"message":{"id":"msg_side","usage":{"input_tokens":30,"output_tokens":15,"cache_read_input_tokens":5,"cache_creation_input_tokens":2}},"requestId":"req_side","type":"assistant","uuid":"uuid-side","timestamp":"2026-07-06T09:00:00.000Z"}
    """

  static let malformedLine = """
    {not valid json at all
    """

  static let legacyTopLevelUsage = """
    {"message_id": "msg_legacy", "timestamp": 1700000000, "usage": {"input_tokens": 100, "output_tokens": 50, "cache_read_input_tokens": 20, "cache_creation_input_tokens": 10}}
    """

  static let epochTimestampLine = """
    {"message":{"id":"msg_epoch","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}},"requestId":"req_epoch","type":"assistant","uuid":"uuid-epoch","timestamp":1700000000}
    """

  static let oauthUsageResponse = """
    {
        "five_hour": {
            "utilization": 8.0,
            "resets_at": "2026-07-09T01:00:00.475743+00:00",
            "limit_dollars": null,
            "used_dollars": null,
            "remaining_dollars": null
        },
        "seven_day": {
            "utilization": 62.0,
            "resets_at": "2026-07-13T02:00:00.475765+00:00",
            "limit_dollars": null,
            "used_dollars": null,
            "remaining_dollars": null
        },
        "seven_day_oauth_apps": null,
        "seven_day_opus": null,
        "seven_day_sonnet": null,
        "seven_day_cowork": null,
        "seven_day_omelette": null,
        "tangelo": null,
        "iguana_necktie": null,
        "omelette_promotional": null,
        "nimbus_quill": null,
        "cinder_cove": null,
        "amber_ladder": null,
        "extra_usage": {
            "is_enabled": false,
            "monthly_limit": 5000,
            "used_credits": 2152.0,
            "utilization": 43.04,
            "currency": "USD",
            "decimal_places": 2,
            "disabled_reason": "out_of_credits",
            "daily": null,
            "weekly": null
        },
        "limits": [
            {
                "kind": "session",
                "group": "session",
                "percent": 8,
                "severity": "normal",
                "resets_at": "2026-07-09T01:00:00.475743+00:00",
                "scope": null,
                "is_active": false
            },
            {
                "kind": "weekly_all",
                "group": "weekly",
                "percent": 62,
                "severity": "normal",
                "resets_at": "2026-07-13T02:00:00.475765+00:00",
                "scope": null,
                "is_active": true
            },
            {
                "kind": "weekly_scoped",
                "group": "weekly",
                "percent": 49,
                "severity": "normal",
                "resets_at": "2026-07-13T02:00:00.476071+00:00",
                "scope": {
                    "model": {
                        "id": null,
                        "display_name": "Fable"
                    },
                    "surface": null
                },
                "is_active": false
            }
        ],
        "spend": {
            "used": {
                "amount_minor": 2152,
                "currency": "USD",
                "exponent": 2
            },
            "limit": {
                "amount_minor": 5000,
                "currency": "USD",
                "exponent": 2
            },
            "percent": 43,
            "severity": "normal",
            "enabled": false,
            "disabled_reason": "out_of_credits",
            "cap": {
                "money": null,
                "credits": {
                    "amount_minor": 5000,
                    "exponent": 2
                }
            },
            "balance": null,
            "auto_reload": null,
            "disclaimer": "Usage credits cover you when you hit your plan limits. [Learn more](https://support.claude.com/articles/12429409)",
            "can_purchase_credits": false,
            "can_toggle": false
        },
        "member_dashboard_available": false
    }
    """

  static let isoTimestampLine = """
    {"message":{"id":"msg_iso","usage":{"input_tokens":20,"output_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}},"requestId":"req_iso","type":"assistant","uuid":"uuid-iso","timestamp":"2026-07-06T07:55:59Z"}
    """

  static func twoDistinctMessages() -> String {
    """
    {"message":{"id":"msg_a","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":20,"cache_creation_input_tokens":10}},"requestId":"req_a","type":"assistant","uuid":"uuid-a","timestamp":"2026-07-06T10:00:00.000Z"}
    {"message":{"id":"msg_b","usage":{"input_tokens":200,"output_tokens":100,"cache_read_input_tokens":30,"cache_creation_input_tokens":15}},"requestId":"req_b","type":"assistant","uuid":"uuid-b","timestamp":"2026-07-06T11:00:00.000Z"}
    """
  }

  static func crossFileDuplicate() -> String {
    """
    {"message":{"id":"msg_shared","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":20,"cache_creation_input_tokens":10}},"requestId":"req_shared","type":"assistant","uuid":"uuid-shared","timestamp":"2026-07-06T10:00:00.000Z"}
    """
  }

  static func validWithMalformed() -> String {
    """
    {"message":{"id":"msg_ok","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}},"requestId":"req_ok","type":"assistant","uuid":"uuid-ok","timestamp":"2026-07-06T10:00:00.000Z"}
    {broken json line
    """
  }

  /// Records at today, week-only, month-only, and outside-month boundaries relative to referenceNow.
  static func windowBucketLines(referenceNow: Date) -> String {
    let cal = Calendar(identifier: .gregorian)
    var utc = cal
    utc.timeZone = TimeZone(identifier: "UTC")!

    let todayStart = utc.startOfDay(for: referenceNow)
    let todayTS = isoString(todayStart.addingTimeInterval(3600), utc: utc)
    let weekTS = isoString(utc.date(byAdding: .day, value: -3, to: todayStart)!, utc: utc)
    let monthTS = isoString(utc.date(byAdding: .day, value: -20, to: todayStart)!, utc: utc)
    let outsideTS = isoString(utc.date(byAdding: .month, value: -2, to: todayStart)!, utc: utc)

    func line(id: String, input: Int, timestamp: String) -> String {
      """
      {"message":{"id":"\(id)","usage":{"input_tokens":\(input),"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}},"requestId":"req_\(id)","type":"assistant","uuid":"uuid_\(id)","timestamp":"\(timestamp)"}
      """
    }

    return [
      line(id: "today", input: 10, timestamp: todayTS),
      line(id: "week", input: 20, timestamp: weekTS),
      line(id: "month", input: 30, timestamp: monthTS),
      line(id: "outside", input: 40, timestamp: outsideTS),
    ].joined(separator: "\n")
  }

  private static func isoString(_ date: Date, utc: Calendar) -> String {
    let comps = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    return String(format: "%04d-%02d-%02dT%02d:%02d:%02d.000Z",
                  comps.year!, comps.month!, comps.day!,
                  comps.hour!, comps.minute!, comps.second!)
  }
}

enum CodexFixtures {
  static let ignoredEvent = """
    {"timestamp":"2026-07-06T08:00:00.000Z","type":"event_msg","payload":{"type":"agent_message","message":"hello"}}
    """

  static let malformedLine = """
    {not valid codex json
    """

  static func twoTokenCountEvents() -> String {
    """
    {"timestamp":"2026-07-06T10:00:00.123Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":30,"reasoning_output_tokens":10,"total_tokens":130},"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":30,"reasoning_output_tokens":10,"total_tokens":130},"model_context_window":258400},"rate_limits":{"limit_id":"codex","primary":{"used_percent":10.0,"window_minutes":300,"resets_at":1783324383},"secondary":{"used_percent":30.0,"window_minutes":10080,"resets_at":1783457462},"credits":null,"plan_type":"plus","rate_limit_reached_type":null}}}
    {"timestamp":"2026-07-06T11:00:00.456Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":150,"cached_input_tokens":25,"output_tokens":50,"reasoning_output_tokens":10,"total_tokens":200},"last_token_usage":{"input_tokens":50,"cached_input_tokens":5,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":70},"model_context_window":258400},"rate_limits":{"limit_id":"codex","primary":{"used_percent":12.5,"window_minutes":300,"resets_at":1783324383},"secondary":{"used_percent":33.0,"window_minutes":10080,"resets_at":1783457462},"credits":null,"plan_type":"plus","rate_limit_reached_type":null}}}
    """
  }

  static func windowBucketLines(referenceNow: Date) -> String {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!

    let todayStart = utc.startOfDay(for: referenceNow)
    let todayTS = isoString(todayStart.addingTimeInterval(3600), utc: utc)
    let weekTS = isoString(utc.date(byAdding: .day, value: -3, to: todayStart)!, utc: utc)
    let monthTS = isoString(utc.date(byAdding: .day, value: -20, to: todayStart)!, utc: utc)
    let outsideTS = isoString(utc.date(byAdding: .month, value: -2, to: todayStart)!, utc: utc)

    func line(id: String, total: Int, timestamp: String) -> String {
      """
      {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(total),"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":\(total)},"last_token_usage":{"input_tokens":\(total),"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":\(total)}},"rate_limits":null}}
      """
    }

    return [
      line(id: "today", total: 10, timestamp: todayTS),
      line(id: "week", total: 20, timestamp: weekTS),
      line(id: "month", total: 30, timestamp: monthTS),
      line(id: "outside", total: 40, timestamp: outsideTS),
    ].joined(separator: "\n")
  }

  /// A `turn_context` model-configuration line (as emitted once per turn by the Codex
  /// CLI) followed by `twoTokenCountEvents()`, so `detectLatestModel` finds `model`.
  static func sessionWithModel(model: String) -> String {
    """
    {"timestamp":"2026-07-06T09:00:00.000Z","type":"turn_context","payload":{"turn_id":"turn-1","model":"\(model)"}}
    \(twoTokenCountEvents())
    """
  }

  static func nullRateLimitFields() -> String {
    """
    {"timestamp":"2026-07-06T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":null,"output_tokens":5,"reasoning_output_tokens":null,"total_tokens":15},"last_token_usage":{"input_tokens":10,"cached_input_tokens":null,"output_tokens":5,"reasoning_output_tokens":null,"total_tokens":15}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":null,"window_minutes":null,"resets_at":null},"secondary":null,"credits":null,"plan_type":null,"rate_limit_reached_type":null}}}
    """
  }

  static func staleRateLimits() -> String {
    """
    {"timestamp":"2026-07-04T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":20,"cached_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":0,"total_tokens":30},"last_token_usage":{"input_tokens":20,"cached_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":0,"total_tokens":30}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":40.0,"window_minutes":300,"resets_at":1783324383},"secondary":{"used_percent":60.0,"window_minutes":10080,"resets_at":1783457462},"credits":null,"plan_type":"plus","rate_limit_reached_type":null}}}
    """
  }

  private static func isoString(_ date: Date, utc: Calendar) -> String {
    let comps = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    return String(format: "%04d-%02d-%02dT%02d:%02d:%02d.000Z",
                  comps.year!, comps.month!, comps.day!,
                  comps.hour!, comps.minute!, comps.second!)
  }
}

enum ClineFixtures {
  static let malformedJSON = """
    {not valid cline json at all
    """

  static func twoAssistantMessages(sessionID: String = "1783325327533_test") -> String {
    """
    {"version":1,"updated_at":1783325327533,"agent":"cline","sessionId":"\(sessionID)","messages":[
      {"id":"msg_a","role":"assistant","ts":1783325327533,"modelInfo":{"id":"cline-pass/kimi-k2.7-code","provider":"cline-pass"},"metrics":{"inputTokens":100,"outputTokens":50,"cacheReadTokens":20,"cacheWriteTokens":10,"cost":0.01}},
      {"id":"msg_b","role":"assistant","ts":1783325407533,"modelInfo":{"id":"cline-pass/kimi-k2.7-code","provider":"cline-pass"},"metrics":{"inputTokens":200,"outputTokens":100,"cacheReadTokens":30,"cacheWriteTokens":15,"cost":0.02}}
    ],"system_prompt":""}
    """
  }

  static func duplicateMessage(sessionID: String = "1783325327533_dup") -> String {
    """
    {"version":1,"sessionId":"\(sessionID)","messages":[
      {"id":"msg_shared","role":"assistant","ts":1783325327533,"metrics":{"inputTokens":100,"outputTokens":50,"cacheReadTokens":20,"cacheWriteTokens":10,"cost":0.01}}
    ]}
    """
  }

  static func messageWithoutMetrics(sessionID: String = "1783325327533_nom") -> String {
    """
    {"version":1,"sessionId":"\(sessionID)","messages":[
      {"id":"msg_no_metrics","role":"assistant","ts":1783325327533},
      {"id":"msg_with_metrics","role":"assistant","ts":1783325327534,"metrics":{"inputTokens":10,"outputTokens":5,"cacheReadTokens":0,"cacheWriteTokens":0,"cost":0.001}}
    ]}
    """
  }

  static func windowBucketMessages(referenceNow: Date, sessionID: String = "1783325327533_win") -> String {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!

    let todayStart = utc.startOfDay(for: referenceNow)
    let todayMillis = millis(todayStart.addingTimeInterval(3600), utc: utc)
    let weekMillis = millis(utc.date(byAdding: .day, value: -3, to: todayStart)!, utc: utc)
    let monthMillis = millis(utc.date(byAdding: .day, value: -20, to: todayStart)!, utc: utc)
    let outsideMillis = millis(utc.date(byAdding: .month, value: -2, to: todayStart)!, utc: utc)

    func message(id: String, input: Int, ts: Int64) -> String {
      """
      {"id":"\(id)","role":"assistant","ts":\(ts),"metrics":{"inputTokens":\(input),"outputTokens":0,"cacheReadTokens":0,"cacheWriteTokens":0,"cost":0.001}}
      """
    }

    return """
    {"version":1,"sessionId":"\(sessionID)","messages":[
      \(message(id: "today", input: 10, ts: todayMillis)),
      \(message(id: "week", input: 20, ts: weekMillis)),
      \(message(id: "month", input: 30, ts: monthMillis)),
      \(message(id: "outside", input: 40, ts: outsideMillis))
    ]}
    """
  }

  private static func millis(_ date: Date, utc: Calendar) -> Int64 {
    Int64(date.timeIntervalSince1970 * 1000)
  }
}

enum CursorFixtures {
  static func dailyTokenStats(
    date: String,
    inputTokens: Int,
    outputTokens: Int,
    cacheReadTokens: Int,
    cacheCreationTokens: Int,
    reasoningTokens: Int
  ) -> String {
    """
    {"date":"\(date)","inputTokens":\(inputTokens),"outputTokens":\(outputTokens),"cacheReadTokens":\(cacheReadTokens),"cacheCreationTokens":\(cacheCreationTokens),"reasoningTokens":\(reasoningTokens)}
    """
  }

  static func codeLineDailyStats(date: String) -> String {
    """
    {"date":"\(date)","tabSuggestedLines":12,"tabAcceptedLines":3,"composerSuggestedLines":45,"composerAcceptedLines":18}
    """
  }
}

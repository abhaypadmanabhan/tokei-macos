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

import Foundation

extension CodexFixtures {
  static func d5CumulativeSequence(
    timestamps: [String] = [
      "2026-07-06T10:00:00.000Z",
      "2026-07-06T11:00:00.000Z",
      "2026-07-06T12:00:00.000Z",
    ],
    cumulative: [Int] = [100, 100, 150],
    deltas: [Int] = [100, 100, 50],
    quotaPercents: [Double] = [10, 20, 30]
  ) -> [String] {
    zip(zip(timestamps, cumulative), zip(deltas, quotaPercents)).map { left, right in
      let (timestamp, cumulativeTotal) = left
      let (delta, quotaPercent) = right
      return """
      {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(cumulativeTotal),"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":\(cumulativeTotal)},"last_token_usage":{"input_tokens":\(delta),"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":\(delta)}},"rate_limits":{"plan_type":"plus","primary":{"used_percent":\(quotaPercent),"limit_window_seconds":18000,"resets_at":1783324383},"secondary":{"used_percent":\(quotaPercent),"limit_window_seconds":604800,"resets_at":1783457462}}}}
      """
    }
  }

  static func a3QuotaEvent(timestamp: String) -> String {
    """
    {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":10},"last_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":10}},"rate_limits":{"plan_type":"pro","primary":{"used_percent":5,"limit_window_seconds":18000,"resets_at":1783324383},"secondary":{"used_percent":30,"limit_window_seconds":604800,"resets_at":1783457462},"spend_control":{"individual_limit":{"used_percent":20,"remaining_percent":80}},"credits":{"balance":80,"limit":100},"rate_limit_reset_credits":{"available":3}}}}
    """
  }
}

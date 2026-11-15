import Foundation

/// Opt-in counters for scripts/perf-bench.sh. No log paths or account data are emitted.
public enum PerformanceProbe {
    public static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["TOKEI_PERF_PROBE"] == "1"
    }

    public static func emit(_ event: String, fields: [String: String] = [:]) {
        guard isEnabled else { return }
        var payload = fields
        payload["event"] = event
        payload["timestamp"] = String(Date().timeIntervalSince1970)
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        FileHandle.standardError.write(Data("[perf] ".utf8) + data + Data("\n".utf8))
    }
}

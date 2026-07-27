import Foundation

public protocol LocalLogProvider: Sendable {
    /// Every log file this provider can read, across every account/root it is configured
    /// with.
    ///
    /// Partial failure is absorbed; total failure is not. An implementation that reads
    /// several roots returns the union of the roots that worked, and throws only when
    /// **every root that exists** failed. A root that isn't there is *absent*, not broken:
    /// it is skipped silently, so a tool the user never installed reads as "nothing to
    /// report" rather than as an error. Callers therefore get exactly three outcomes:
    ///
    /// - a non-empty array — these sessions exist (some roots may have failed silently);
    /// - an empty array — discovery succeeded and there is genuinely nothing to read;
    /// - a throw — nothing could be read at all, and the count is unknown.
    ///
    /// The distinction is load-bearing: an empty array is reported to the user as "no
    /// sessions yet", so a broken directory must never produce one. Callers that need
    /// per-root diagnostics (`ClaudeCodeProvider.fetchSnapshot`) read the roots
    /// individually instead and surface a warning per failure.
    func discoverLogSources() async throws -> [LogSource]
}

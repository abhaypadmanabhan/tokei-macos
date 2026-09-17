import Foundation

extension MCPServer {
    /// MCP clients surface this to the model once at connect time, so the trigger and
    /// trust rules persist for the session instead of depending on per-tool descriptions.
    static let instructions = """
        Tokei reports how much quota is left across the AI coding tools on this Mac \
        (Claude Code, Codex, Cursor, Cline, Gemini, Antigravity, Copilot, opencode).

        When to call, without being asked:
        • BEFORE spawning, delegating to, or orchestrating another coding agent or \
        subagent — check where there is room, then pick the target.
        • BEFORE starting a long, parallel, or fan-out job that will consume a \
        provider's quota.
        • When the user asks what they have left, what a plan is worth, or which \
        tool to use for a task.

        Routing work to a provider that is about to hit its limit wastes the run and \
        the user's money. Check first, then choose.

        Reading the result:
        • Treat any provider at or above 85% utilization as unavailable; prefer the \
        least-utilized one that reported real quota.
        • `confidence: official` is provider-reported. Never treat `local_estimate` \
        or `unavailable` as a hard limit — they are floors, not ceilings.
        • A low number you do not trust is NOT free capacity. A stale or estimated 0% \
        means "no reading", not "wide open" — absence of data is not headroom.
        • `observedAt` on a window is when that reading was taken. The top-level \
        `stale` flag is a different thing: it only says how long ago Tokei wrote the \
        file, so `stale: false` can still contain hour-old numbers. Judge freshness \
        per window.
        • `accounts[].accountID` is the opaque, provider-scoped identity. For known \
        identities it is stable across machines. `accounts[].id` is only a legacy \
        local locator; never join accounts on it.
        • To act on `recommendation.target.selector.env`, pass that map as the \
        environment argument to the process API. Never concatenate selector values \
        into a shell string.
        • Feature-detect `accountID` and `target`. An older helper in front of a newer \
        app is a lossy proxy even though both snapshots use schema version 1.
        • `quota.status` is `eligible`, `expiredCredentials`, `cooldown`, `disabled`, \
        `requestFailed`, `noQuotaSource`, or `unknown`. Only `eligible` publishes \
        positive headroom and a bounded `validUntil` decision.
        • If `stale` is true, Tokei may not be running or the recommendation expired. \
        Say so instead of presenting the numbers as current.

        Read-only. No network, no credentials, no other application's data.
        """
}

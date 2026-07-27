import Foundation

/// Fixtures for the `tokei` CLI / MCP surface (issue #59). These are the **frozen
/// agent-snapshot wire contract** as an external agent sees it on disk — string
/// literals, never resource files, so a schema drift shows up as a diff in this file.
///
/// The provider mix is deliberate and each entry earns its place:
///   • `claude_code`  — two `official` windows + a multi-account breakdown (f725bac)
///   • `codex`        — one `official` window over the 85% avoid line
///   • `cursor`       — **empty `windows[]`** with a real token count: must render as
///                      "—", never as 0%, and must never be a routing target
///   • `antigravity`  — a `local_estimate` 0% window: a low number you do not trust is
///                      not free capacity, so it must not be the routing target either
///
/// **`full` must stay a snapshot the real engine could actually emit.** A fixture that
/// pairs an impossible number with a real decision teaches the wrong contract to every
/// test that reads it, so the two derived values below are pinned to their sources:
/// `codexUsedPercent` to `AgentRecommendationEngine.avoidThreshold`, and
/// `aggregateUtilizationPercent` to the mean of the per-provider peaks.
enum AgentSnapshotFixtures {
  /// `generatedAt` of `full` / `minimal` / `newerSchemaVersion`, as a Date.
  static let generatedAt = Date(timeIntervalSince1970: 1_785_153_600) // 2026-07-27T12:00:00Z

  /// Codex's `usedPercent` in `full`. Must stay **at or above**
  /// `AgentRecommendationEngine.avoidThreshold` (85), because the same fixture hard-codes
  /// `avoid: ["codex"]` — the engine only avoids at `>= 85`, so a lower number here would
  /// make `full` an output production could never produce. 88, not 85, so the fixture is
  /// never sitting on the boundary. Asserted against the live constant in
  /// `StatusFormattingTests.testAvoidedProviderIsNamed`.
  static let codexUsedPercent = 88

  /// `full`'s `aggregateUtilizationPercent`. `UtilizationEngine.aggregate` is the mean of
  /// each provider's **peak** window: Claude 5 (max of 4/5), Codex 88, Antigravity 0.
  /// Cursor has no windows at all, so it is absent from `peakByProvider` and is not
  /// averaged in. (5 + 88 + 0) / 3 = 31.
  static let aggregateUtilizationPercent = 31

  static let full = """
    {
      "schemaVersion": 1,
      "generatedAt": "2026-07-27T12:00:00Z",
      "aggregateUtilizationPercent": 31,
      "providers": [
        {
          "id": "claude_code",
          "displayName": "Claude Code",
          "tokensToday": 277000000,
          "lastUpdated": "2026-07-27T11:58:00Z",
          "windows": [
            {"type": "fiveHour", "usedPercent": 4, "confidence": "official",
             "source": "oauth_usage_api", "observedAt": "2026-07-27T11:58:00Z"},
            {"type": "weekly", "usedPercent": 5, "confidence": "official",
             "source": "oauth_usage_api", "resetsAt": "2099-01-01T00:00:00Z",
             "observedAt": "2026-07-27T11:58:00Z"}
          ],
          "accounts": [
            {"id": "/Users/test/.claude", "label": "default", "tokensToday": 120000000,
             "windows": [{"type": "weekly", "usedPercent": 31, "confidence": "official",
                          "source": "oauth_usage_api"}]},
            {"id": "/Users/test/.claude-account-2", "label": "account-2", "tokensToday": 157000000,
             "windows": [{"type": "weekly", "usedPercent": 5, "confidence": "official",
                          "source": "oauth_usage_api"}]}
          ]
        },
        {
          "id": "codex",
          "displayName": "OpenAI Codex",
          "tokensToday": 4100000,
          "lastUpdated": "2026-07-27T11:57:00Z",
          "windows": [
            {"type": "weekly", "usedPercent": 88, "confidence": "official",
             "source": "codex_rate_limits", "observedAt": "2026-07-27T11:57:00Z"}
          ]
        },
        {
          "id": "cursor",
          "displayName": "Cursor",
          "tokensToday": 1380000,
          "lastUpdated": "2026-07-27T11:40:00Z",
          "windows": []
        },
        {
          "id": "antigravity",
          "displayName": "Antigravity",
          "windows": [
            {"type": "weekly", "usedPercent": 0, "confidence": "local_estimate",
             "source": "antigravity-local-rpc"}
          ]
        }
      ],
      "recommendation": {
        "routeTo": "claude_code",
        "avoid": ["codex"],
        "reason": "route to Claude Code (tightest trusted window 5%); \
    excluded antigravity (local_estimate), cursor (no window)"
      }
    }
    """

  /// No providers, no recommendation — the "app just launched" shape.
  static let minimal = """
    {"schemaVersion": 1, "generatedAt": "2026-07-27T12:00:00Z", "providers": []}
    """

  /// Forward-compat contract: a reader must decode what it understands from a NEWER
  /// schema rather than refusing the file. `schemaVersion` itself stays 1 for anything
  /// Tokei writes — this fixture models a future writer, not a change to the contract.
  static let newerSchemaVersion = """
    {
      "schemaVersion": 2,
      "generatedAt": "2026-07-27T12:00:00Z",
      "somethingTheFutureAdded": {"nested": true},
      "providers": [
        {"id": "claude_code", "displayName": "Claude Code", "windows": [
          {"type": "weekly", "usedPercent": 5, "confidence": "official",
           "source": "oauth_usage_api", "unknownWindowField": 1}
        ]}
      ]
    }
    """

  static let malformedJSON = """
    {"schemaVersion": 1, "generatedAt": "2026-07-27T12:00:00Z", "providers": [
    """
}

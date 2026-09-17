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
/// `codexUsedPercent` to `AgentRecommendationEngine.policy.avoidThreshold`, and
/// `aggregateUtilizationPercent` to the mean of the per-provider peaks.
enum AgentSnapshotFixtures {
  /// A5's additive-v1 acceptance oracle from t03. Ordering is intentionally irrelevant;
  /// `AgentSnapshotAccountSchemaTests` compares the decoded JSON object field-by-field.
  static let wp5SchemaAfter = #"""
  {
    "ageSeconds": 6,
    "aggregateUtilizationPercent": 56,
    "generatedAt": "2026-09-17T02:16:40Z",
    "providers": [
      {
        "accounts": [
          {
            "id": "/Users/abhayp/.claude",
            "label": "default",
            "tokensToday": 0,
            "windows": [],
            "accountID": "claude_code:c99dd9a2310dcd8ac8bf64432cf3e2b91b51e9488e15ccffbdcc681be8792ec2",
            "selector": {"env": {"CLAUDE_CONFIG_DIR": "/Users/abhayp/.claude"}},
            "quota": {"status": "unknown", "reasonCode": "no_quota_reading"}
          },
          {
            "id": "/Users/abhayp/.claude-account-1",
            "label": "account-1",
            "tokensToday": 553069448,
            "windows": [
              {
                "confidence": "official",
                "observedAt": "2026-09-17T02:14:00Z",
                "resetsAt": "2026-09-17T03:40:00Z",
                "source": "api.anthropic.com/api/oauth/usage",
                "type": "session",
                "usedPercent": 9
              },
              {
                "confidence": "official",
                "observedAt": "2026-09-17T02:14:00Z",
                "resetsAt": "2026-09-21T01:59:59Z",
                "source": "api.anthropic.com/api/oauth/usage",
                "type": "weekly",
                "usedPercent": 81
              },
              {
                "confidence": "official",
                "observedAt": "2026-09-17T02:14:00Z",
                "resetsAt": "2026-09-21T01:59:59Z",
                "source": "api.anthropic.com/api/oauth/usage",
                "type": "perModel",
                "usedPercent": 81
              }
            ],
            "accountID": "claude_code:41b5e8112aea16297b2abf8229b1c429ead077faecea1ea4f904ea26ee76a2e4",
            "selector": {"env": {"CLAUDE_CONFIG_DIR": "/Users/abhayp/.claude-account-1"}},
            "quota": {
              "status": "eligible",
              "usedPercent": 81,
              "headroomPercent": 19,
              "bindingWindowIndex": 1,
              "validUntil": "2026-09-17T02:26:40Z"
            }
          }
        ],
        "displayName": "Claude Code",
        "id": "claude_code",
        "lastUpdated": "2026-09-17T02:16:39Z",
        "tokensToday": 553069448,
        "windows": [
          {
            "confidence": "official",
            "observedAt": "2026-09-17T02:14:00Z",
            "resetsAt": "2026-09-17T03:40:00Z",
            "source": "api.anthropic.com/api/oauth/usage",
            "type": "session",
            "usedPercent": 9
          },
          {
            "confidence": "official",
            "observedAt": "2026-09-17T02:14:00Z",
            "resetsAt": "2026-09-21T01:59:59Z",
            "source": "api.anthropic.com/api/oauth/usage",
            "type": "weekly",
            "usedPercent": 81
          },
          {
            "confidence": "official",
            "observedAt": "2026-09-17T02:14:00Z",
            "resetsAt": "2026-09-21T01:59:59Z",
            "source": "api.anthropic.com/api/oauth/usage",
            "type": "perModel",
            "usedPercent": 81
          }
        ],
        "headlineAccountID": "claude_code:41b5e8112aea16297b2abf8229b1c429ead077faecea1ea4f904ea26ee76a2e4"
      },
      {
        "displayName": "OpenAI Codex",
        "id": "codex",
        "lastUpdated": "2026-09-17T02:16:39Z",
        "tokensToday": 121521151,
        "windows": [
          {
            "confidence": "official",
            "resetsAt": "2026-09-21T05:26:47Z",
            "source": "Codex CLI rate_limits (pro plan, weekly window)",
            "type": "weekly",
            "usedPercent": 31,
            "observedAt": "2026-09-17T02:14:00Z"
          }
        ],
        "accounts": [
          {
            "id": "/Users/abhayp/.codex",
            "accountID": "codex:a0aba5417af6496ff20d401d87bfb39c579039a08de804bbfe225a18e8c41e25",
            "label": "default",
            "windows": [
              {
                "confidence": "official",
                "resetsAt": "2026-09-21T05:26:47Z",
                "source": "Codex CLI rate_limits (pro plan, weekly window)",
                "type": "weekly",
                "usedPercent": 31,
                "observedAt": "2026-09-17T02:14:00Z"
              }
            ],
            "tokensToday": 121521151,
            "selector": {"env": {"CODEX_HOME": "/Users/abhayp/.codex"}},
            "quota": {
              "status": "eligible",
              "usedPercent": 31,
              "headroomPercent": 69,
              "bindingWindowIndex": 0,
              "validUntil": "2026-09-17T02:26:40Z"
            }
          }
        ],
        "headlineAccountID": "codex:a0aba5417af6496ff20d401d87bfb39c579039a08de804bbfe225a18e8c41e25"
      }
    ],
    "recommendation": {
      "routeTo": "codex",
      "avoid": [],
      "reason": "route to OpenAI Codex (tightest window 31%)",
      "target": {
        "provider": "codex",
        "accountID": "codex:a0aba5417af6496ff20d401d87bfb39c579039a08de804bbfe225a18e8c41e25",
        "selector": {"env": {"CODEX_HOME": "/Users/abhayp/.codex"}}
      },
      "avoidAccounts": [],
      "validUntil": "2026-09-17T02:26:40Z"
    },
    "schemaVersion": 1,
    "stale": false
  }
  """#

  /// `generatedAt` of `full` / `minimal` / `newerSchemaVersion`, as a Date.
  static let generatedAt = Date(timeIntervalSince1970: 1_785_153_600) // 2026-07-27T12:00:00Z

  /// Codex's `usedPercent` in `full`. Must stay **at or above**
  /// `AgentRecommendationEngine.policy.avoidThreshold` (85) — the threshold of the tuning
  /// the engine actually applies, now that the rule itself lives on `RouteTargetPolicy` —
  /// because the same fixture hard-codes `avoid: ["codex"]`. The engine only avoids at
  /// `>= 85`, so a lower number here would make `full` an output production could never
  /// produce. 88, not 85, so the fixture is never sitting on the boundary. Asserted
  /// against the live value in
  /// `StatusFormattingTests.testFixtureAvoidDecisionMatchesTheFrozenThreshold`.
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

  /// D7: both accounts must remain visible in text status even when one has no quota
  /// window. Zero tokens and no window is unknown capacity, not a 0% reading.
  static let twoAccountsOneWithoutQuota = """
    {
      "schemaVersion": 1,
      "generatedAt": "2026-07-27T12:00:00Z",
      "providers": [
        {
          "id": "claude_code",
          "displayName": "Claude Code",
          "tokensToday": 157000000,
          "windows": [
            {"type": "weekly", "usedPercent": 81, "confidence": "official",
             "source": "oauth_usage_api"}
          ],
          "accounts": [
            {"id": "/Users/test/.claude", "label": "default", "tokensToday": 0,
             "windows": []},
            {"id": "/Users/test/.claude-account-1", "label": "account-1",
             "tokensToday": 157000000,
             "windows": [
               {"type": "weekly", "usedPercent": 81, "confidence": "official",
                "source": "oauth_usage_api"}
             ]}
          ]
        }
      ]
    }
    """

  static let routeToAbsent = """
    {
      "schemaVersion": 1,
      "generatedAt": "2026-07-27T12:00:00Z",
      "providers": [],
      "recommendation": {"avoid": ["codex"], "reason": "fixture"}
    }
    """

  static let routeToNull = """
    {
      "schemaVersion": 1,
      "generatedAt": "2026-07-27T12:00:00Z",
      "providers": [],
      "recommendation": {"routeTo": null, "avoid": ["codex"], "reason": "fixture"}
    }
    """

  static let oldOptionalFieldsAbsent = """
    {
      "schemaVersion": 1,
      "generatedAt": "2026-07-27T12:00:00Z",
      "providers": [
        {
          "id": "codex",
          "displayName": "Codex",
          "windows": [
            {"type": "weekly", "usedPercent": 20, "confidence": "official",
             "source": "fixture"}
          ]
        }
      ]
    }
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

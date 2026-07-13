import Foundation

/// String-literal fixtures for `PricingService` / `LiteLLMPricingTableRefresher`.
///
/// Per the Patch Bible §4, this package keeps its fixtures in its own file rather
/// than editing the shared `Fixtures.swift`. Values are illustrative, not the real
/// LiteLLM numbers — tests compute expectations from these literals.
enum PricingFixtures {
    /// A slice mimicking LiteLLM's `model_prices_and_context_window.json` shape:
    /// a dict of model → spec, carrying many non-cost fields, a `sample_spec`
    /// documentation stub, a metadata-only row, and a row whose price should be
    /// overridden by the curated seed.
    static let liteLLMTableJSON = """
    {
      "sample_spec": {
        "max_tokens": 2048,
        "input_cost_per_token": 0.0,
        "output_cost_per_token": 0.0,
        "litellm_provider": "one of the providers",
        "mode": "one of: chat, embedding"
      },
      "gpt-5": {
        "max_tokens": 128000,
        "max_input_tokens": 272000,
        "input_cost_per_token": 0.00000999,
        "output_cost_per_token": 0.00001,
        "cache_read_input_token_cost": 0.000001,
        "litellm_provider": "openai",
        "mode": "chat",
        "supports_vision": true
      },
      "deepseek-chat": {
        "max_tokens": 8192,
        "input_cost_per_token": 0.00000027,
        "output_cost_per_token": 0.0000011,
        "cache_read_input_token_cost": 0.00000007,
        "litellm_provider": "deepseek",
        "mode": "chat"
      },
      "mistral-large-latest": {
        "input_cost_per_token": 0.000002,
        "output_cost_per_token": 0.000006,
        "litellm_provider": "mistral",
        "mode": "chat"
      },
      "text-embedding-3-small": {
        "input_cost_per_token": 0.00000002,
        "output_cost_per_token": 0.0,
        "litellm_provider": "openai",
        "mode": "embedding"
      },
      "embed-meta-only": {
        "litellm_provider": "openai",
        "mode": "embedding",
        "max_tokens": 8191
      }
    }
    """

    static var liteLLMTableData: Data { Data(liteLLMTableJSON.utf8) }

    /// Bytes that are not a valid LiteLLM table (used for the fetch-succeeds-but-
    /// unparseable path).
    static let notATableJSON = "[]"
    static var notATableData: Data { Data(notATableJSON.utf8) }
}

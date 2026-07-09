import Foundation

enum OpencodeFixtures {
    static let assistantWithCost = """
    {
      "role": "assistant",
      "modelID": "gpt-5.2-codex",
      "providerID": "openai",
      "tokens": {
        "input": 212,
        "output": 43,
        "reasoning": 5,
        "cache": { "read": 24192, "write": 11 }
      },
      "cost": 0.07,
      "time": { "created": 1769071614083, "completed": 1769071616741 }
    }
    """

    static let assistantWithoutCost = """
    {
      "role": "assistant",
      "modelID": "gpt-5.2-codex",
      "providerID": "openai",
      "tokens": {
        "input": 100,
        "output": 20,
        "reasoning": 0,
        "cache": { "read": 300, "write": 7 }
      },
      "cost": 0,
      "time": { "created": 1768812414083, "completed": 1768812416741 }
    }
    """

    static let userWithoutTokens = """
    {
      "role": "user",
      "providerID": "openai",
      "time": { "created": 1769071600000 }
    }
    """

    static func assistant(
        id: String,
        createdMillis: Int64,
        input: Int,
        output: Int,
        cacheRead: Int,
        cacheWrite: Int,
        reasoning: Int = 0,
        cost: Double = 0
    ) -> String {
        """
        {
          "id": "\(id)",
          "role": "assistant",
          "modelID": "gpt-5.2-codex",
          "providerID": "openai",
          "tokens": {
            "input": \(input),
            "output": \(output),
            "reasoning": \(reasoning),
            "cache": { "read": \(cacheRead), "write": \(cacheWrite) }
          },
          "cost": \(cost),
          "time": { "created": \(createdMillis), "completed": \(createdMillis + 1000) }
        }
        """
    }

    static func user(createdMillis: Int64) -> String {
        """
        {
          "role": "user",
          "providerID": "openai",
          "time": { "created": \(createdMillis) }
        }
        """
    }
}

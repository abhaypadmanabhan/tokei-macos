import XCTest
@testable import AIUsageDashboardCore

/// WP-3 addendum 1: "Value by model" shows the base model with its tier as a word, never
/// the raw `@` key WP-1 stores for fast-tier pricing. Keys are the ones WP-1 writes
/// (`model + "@fast"` for Claude `speed == "fast"`, `@priority`/`@ultrafast` for Codex).
final class ModelKeyNameTests: XCTestCase {
    func testTierKeysSplitIntoNameAndTier() {
        XCTAssertEqual(ModelKeyName("gpt-5.5@priority").name, "gpt-5.5")
        XCTAssertEqual(ModelKeyName("gpt-5.5@priority").tier, "priority")
        XCTAssertEqual(ModelKeyName("gpt-5.5@ultrafast").name, "gpt-5.5")
        XCTAssertEqual(ModelKeyName("gpt-5.5@ultrafast").tier, "ultrafast")
        XCTAssertEqual(ModelKeyName("claude-opus-5-5@fast").name, "claude-opus-5-5")
        XCTAssertEqual(ModelKeyName("claude-opus-5-5@fast").tier, "fast")
    }

    func testPlainKeyHasNoTier() {
        XCTAssertEqual(ModelKeyName("gpt-5.5").name, "gpt-5.5")
        XCTAssertNil(ModelKeyName("gpt-5.5").tier)
    }

    /// Vertex model ids carry a date after `@`; that is part of the name, not a tier.
    func testVertexDateSuffixStaysInTheName() {
        XCTAssertEqual(ModelKeyName("claude-3-5-sonnet@20240620").name, "claude-3-5-sonnet@20240620")
        XCTAssertNil(ModelKeyName("claude-3-5-sonnet@20240620").tier)
    }

    func testBareTierIsNotAModelWithATier() {
        XCTAssertEqual(ModelKeyName("@fast").name, "@fast")
        XCTAssertNil(ModelKeyName("@fast").tier)
    }

    func testSpokenNameNeverSaysTheAtKey() {
        XCTAssertEqual(ModelKeyName("gpt-5.5@priority").spoken, "gpt-5.5, priority tier")
        XCTAssertEqual(ModelKeyName("claude-opus-5-5").spoken, "claude-opus-5-5")
    }
}

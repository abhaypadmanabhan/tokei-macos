import XCTest
@testable import AIUsageDashboardCore

final class PlanPresetTests: XCTestCase {
    // MARK: Preset → price mapping

    func testKnownProvidersMapToPublishedPresetPrices() {
        XCTAssertEqual(PlanPresetCatalog.presets(for: "cursor"), [
            PlanPreset(id: "cursor_pro", label: "Pro", monthlyUSD: 20)
        ])
        XCTAssertEqual(PlanPresetCatalog.presets(for: "codex"), [
            PlanPreset(id: "codex_plus", label: "Plus", monthlyUSD: 20)
        ])
        XCTAssertEqual(PlanPresetCatalog.presets(for: "cline"), [
            PlanPreset(id: "cline_pro", label: "Pro", monthlyUSD: 10)
        ])
        XCTAssertEqual(PlanPresetCatalog.presets(for: "antigravity"), [
            PlanPreset(id: "antigravity_pro", label: "Pro", monthlyUSD: 5)
        ])
        XCTAssertEqual(PlanPresetCatalog.presets(for: "claude_code"), [
            PlanPreset(id: "claude_pro", label: "Pro", monthlyUSD: 20),
            PlanPreset(id: "claude_max", label: "Max", monthlyUSD: 100)
        ])
    }

    func testUnknownProviderHasNoPresets() {
        XCTAssertEqual(PlanPresetCatalog.presets(for: "gemini"), [])
        XCTAssertEqual(PlanPresetCatalog.presets(for: "not_a_real_provider"), [])
    }

    // MARK: Cursor detection

    func testCursorDetectionMatchesComposedPlanLabel() {
        let detected = PlanDetector.detectCursorPlan(planLabel: "Pro (active)")
        XCTAssertEqual(detected?.presetID, "cursor_pro")
        XCTAssertEqual(detected?.monthlyUSD, 20)
    }

    func testCursorDetectionMatchesBareMembershipType() {
        // `summary.membershipType` alone (no composed status suffix), lowercase.
        let detected = PlanDetector.detectCursorPlan(planLabel: "pro")
        XCTAssertEqual(detected?.presetID, "cursor_pro")
        XCTAssertEqual(detected?.monthlyUSD, 20)
    }

    // MARK: Unknown → nil, never $0

    func testUnrecognizedOrMissingCursorPlanLabelDetectsNil() {
        XCTAssertNil(PlanDetector.detectCursorPlan(planLabel: nil))
        XCTAssertNil(PlanDetector.detectCursorPlan(planLabel: "Free (active)"))
        XCTAssertNil(PlanDetector.detectCursorPlan(planLabel: "Business"))
        XCTAssertNil(PlanDetector.detectCursorPlan(planLabel: ""))
    }

    func testResearchStubProvidersAlwaysDetectNil() {
        XCTAssertNil(PlanDetector.detectClaudePlan())
        XCTAssertNil(PlanDetector.detectGeminiPlan())
        XCTAssertNil(PlanDetector.detectAntigravityPlan())
        XCTAssertNil(PlanDetector.detectClinePlan())
        XCTAssertNil(PlanDetector.detectCodexPlan())
    }

    // MARK: Detection never overwrites a user-entered value

    func testSuggestedPlanIsNilWhenUserAlreadyHasAStoredValue() {
        let detected = DetectedPlan(presetID: "cursor_pro", monthlyUSD: 20, source: "Cursor's reported plan")
        XCTAssertNil(PlanDetector.suggestedPlan(existingValue: 100, detected: detected))
        // Even when the stored value happens to equal the detected one.
        XCTAssertNil(PlanDetector.suggestedPlan(existingValue: 20, detected: detected))
    }

    func testSuggestedPlanSurfacesDetectionOnlyWhenUnset() {
        let detected = DetectedPlan(presetID: "cursor_pro", monthlyUSD: 20, source: "Cursor's reported plan")
        XCTAssertEqual(PlanDetector.suggestedPlan(existingValue: nil, detected: detected), detected)
        XCTAssertNil(PlanDetector.suggestedPlan(existingValue: nil, detected: nil))
    }
}

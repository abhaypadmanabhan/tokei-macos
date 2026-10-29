import XCTest
@testable import AIUsageDashboardCore

/// WP-3 AC3: a quota row without a live reading says why, and never sits on "FETCHING…"
/// after the sync has finished.
final class QuotaGapTests: XCTestCase {
    private func gap(_ id: ProviderID, enabled: Bool, syncing: Bool = false, reason: String? = nil) -> QuotaGap {
        QuotaGap.classify(id, isEnabled: { _ in enabled }, isSyncing: syncing, reason: reason)
    }

    func testToggleOffSaysOffWhateverTheSyncIsDoing() {
        XCTAssertEqual(gap(.claudeCode, enabled: false), .networkOff)
        XCTAssertEqual(gap(.cursor, enabled: false, syncing: true), .networkOff)
        XCTAssertEqual(gap(.codex, enabled: false), .networkOff)
    }

    /// The old row said "FETCHING…" forever; now "checking" only while a sync runs.
    func testCheckingOnlyWhileSyncing() {
        XCTAssertEqual(gap(.antigravity, enabled: true, syncing: true), .checking)
        XCTAssertEqual(gap(.antigravity, enabled: true, syncing: false), .noReading(reason: nil))
        XCTAssertEqual(
            gap(.claudeCode, enabled: true, reason: "sign-in expired"),
            .noReading(reason: "sign-in expired")
        )
    }

    func testProvidersWithoutAConnectorHaveNoSource() {
        XCTAssertEqual(gap(.cline, enabled: true), .noSource)
        XCTAssertEqual(gap(.opencode, enabled: true), .noSource)
        XCTAssertEqual(gap(.copilot, enabled: true, syncing: true), .noSource)
        // Codex reads local logs when its probe has nothing: not a pending reading.
        XCTAssertEqual(gap(.codex, enabled: true, syncing: true), .noSource)
    }

    /// AC7: Gemini's network row comes from ProviderMetadata, on until turned off.
    func testGeminiHasANetworkToggleThatDefaultsOn() throws {
        XCTAssertEqual(ProviderMetadata.liveQuotaEnabledKey(for: .gemini), "geminiNetworkUsageEnabled")
        XCTAssertTrue(ProviderMetadata.liveQuotaProviders.contains(.gemini))
        XCTAssertEqual(ProviderMetadata.networkDefaultsOn["geminiNetworkUsageEnabled"], true)
        let suite = "wp3.gemini.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.register(defaults: ProviderMetadata.networkDefaultsOn)
        XCTAssertTrue(defaults.bool(forKey: "geminiNetworkUsageEnabled"))
        defaults.set(false, forKey: "geminiNetworkUsageEnabled")
        XCTAssertFalse(defaults.bool(forKey: "geminiNetworkUsageEnabled"))
    }

    func testReasonComesFromAccountStatus() {
        func snapshot(_ status: AccountQuotaStatus) -> ProviderSnapshot {
            ProviderSnapshot(
                providerID: .claudeCode, displayName: "Claude Code", authStatus: .authenticated,
                todayUsage: .unavailable, weekUsage: .unavailable,
                accounts: [ProviderAccountUsage(
                    id: "/a", label: "default", quotaWindows: [], todayUsage: .unavailable, quotaStatus: status
                )]
            )
        }
        XCTAssertEqual(QuotaGap.reason(for: snapshot(.expiredCredentials)), "sign-in expired")
        XCTAssertEqual(QuotaGap.reason(for: snapshot(.cooldown)), "rate-limited, will retry")
        XCTAssertEqual(QuotaGap.reason(for: snapshot(.requestFailed)), "the request failed")
        XCTAssertNil(QuotaGap.reason(for: snapshot(.eligible)))
        XCTAssertNil(QuotaGap.reason(for: nil))
    }
}

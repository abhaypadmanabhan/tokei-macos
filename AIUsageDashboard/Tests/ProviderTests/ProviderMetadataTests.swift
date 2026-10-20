import SwiftUI
import XCTest
@testable import AIUsageDashboardCore

final class ProviderMetadataTests: XCTestCase {
    func testCodexWithoutQuotaUsesLocalStateAndKeepsSettingsRow() {
        XCTAssertTrue(ProviderMetadata.liveQuotaProviders.contains(.codex))
        XCTAssertFalse(ProviderMetadata.showsPendingQuota(for: .codex))
        XCTAssertTrue(ProviderMetadata.showsPendingQuota(for: .claudeCode))
        XCTAssertTrue(ProviderMetadata.showsPendingQuota(for: .cursor))
        XCTAssertTrue(ProviderMetadata.showsPendingQuota(for: .antigravity))
        XCTAssertFalse(ProviderMetadata.showsPendingQuota(for: .cline))
    }

    func testKeyLookupDoesNotRegisterDefaults() {
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.registrationDomain)
        var cleared = original
        cleared.removeValue(forKey: CodexProvider.liveQuotaEnabledKey)
        defaults.setVolatileDomain(cleared, forName: UserDefaults.registrationDomain)
        defer { defaults.setVolatileDomain(original, forName: UserDefaults.registrationDomain) }
        let key = ProviderMetadata.liveQuotaEnabledKey(for: .codex)
        XCTAssertEqual(key, CodexProvider.liveQuotaEnabledKey)
        let registered = defaults.volatileDomain(forName: UserDefaults.registrationDomain)
        XCTAssertNil(registered[CodexProvider.liveQuotaEnabledKey])
    }

    func testDefaultsReaderUsesFallbackOnlyWhenUnset() throws {
        let suite = "wp2.reader.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let reader = ProviderUserDefaultsReader(defaults)
        let key = CodexProvider.liveQuotaEnabledKey
        XCTAssertTrue(reader.bool(forKey: key, defaultValue: true))
        XCTAssertFalse(reader.bool(forKey: key))
        defaults.set(false, forKey: key)
        XCTAssertFalse(reader.bool(forKey: key, defaultValue: true))
        defaults.set("YES", forKey: key)
        XCTAssertTrue(reader.bool(forKey: key))
    }

    func testRegisteredFreshInstallRowIsOnAndExplicitOffIsKept() throws {
        let suite = "wp2.settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Same registration as app launch; the row's existing wrapped default is false.
        defaults.register(defaults: CodexProvider.liveQuotaDefaults)
        let row = AppStorage(wrappedValue: false, CodexProvider.liveQuotaEnabledKey, store: defaults)
        XCTAssertTrue(row.wrappedValue)
        defaults.set(false, forKey: CodexProvider.liveQuotaEnabledKey)
        XCTAssertFalse(row.wrappedValue)
    }
}

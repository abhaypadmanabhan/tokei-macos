#if TOKEI_WP2_LIVE_PROOF
// Opt-in live checks loaded by LLDB into this lane's own built Tokei.
// Compile with -D TOKEI_WP2_LIVE_PROOF as a dylib; never linked into the shipped app.
import AIUsageDashboardCore
import Foundation
import UserNotifications

@_cdecl("wp2_refresh_proof")
public func wp2RefreshProof(_ path: UnsafePointer<CChar>) {
    let directory = URL(fileURLWithPath: String(cString: path), isDirectory: true)
    Task { await WP2LiveProof.refresh(directory) }
}

@_cdecl("wp2_notification_proof")
public func wp2NotificationProof(_ path: UnsafePointer<CChar>) {
    let directory = URL(fileURLWithPath: String(cString: path), isDirectory: true)
    Task { await WP2LiveProof.notification(directory) }
}

@_cdecl("wp2_stored_refresh_proof")
public func wp2StoredRefreshProof(_ path: UnsafePointer<CChar>) {
    let directory = URL(fileURLWithPath: String(cString: path), isDirectory: true)
    Task { await WP2LiveProof.unchangedReadings(directory) }
}

private struct CapturedLiveProvider: UsageProvider {
    let snapshot: ProviderSnapshot
    var id: ProviderID { snapshot.providerID }
    var displayName: String { snapshot.displayName }
    var capabilities: ProviderCapabilities { [] }
    func detectAvailability() async -> ProviderAvailability { .installed }
    func authenticate() async throws -> AuthStatus { snapshot.authStatus }
    func fetchSnapshot() async throws -> ProviderSnapshot { snapshot }
}

private enum WP2LiveProof {
    static func write(_ value: [String: Any], name: String, directory: URL) throws {
        try SecureFileWriter.write(
            JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted]),
            to: directory.appendingPathComponent(name)
        )
    }

    private static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIUsageDashboard", isDirectory: true)
    }

    private static func stamp(_ url: URL) -> [String: Any] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return ["missing": true]
        }
        return [
            "mtime": (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0,
            "size": (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            "mode": String((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0, radix: 8)
        ]
    }

    private static func stores() -> [String: Any] {
        Dictionary(uniqueKeysWithValues: ["usage-store.json", "quota-series.json"].map {
            ($0, stamp(support.appendingPathComponent($0)))
        })
    }

    private static func cursor() -> [String: Any] {
        let database = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        return ["main": stamp(database), "wal": stamp(URL(fileURLWithPath: database.path + "-wal"))]
    }

    static func unchangedReadings(_ directory: URL) async {
        let snapshots = await UsageStore.shared.allSnapshots()
        let engine = SyncEngine(
            registry: ProviderRegistry(providers: snapshots.map { CapturedLiveProvider(snapshot: $0) }),
            watcher: FileWatcher(paths: []), evaluateThresholds: { _ in }
        )
        _ = await engine.refreshAll()
        var sequence = [stores()]
        for _ in 0..<2 {
            _ = await engine.refreshAll()
            sequence.append(stores())
        }
        try? write([
            "source": "captured current live app readings; normal auto-sync remains running",
            "providers": snapshots.count, "refreshes": 2, "stores": sequence
        ], name: "unchanged-readings-proof.json", directory: directory)
    }

    static func refresh(_ directory: URL) async {
        do {
            let launch = try String(
                contentsOf: directory.appendingPathComponent("live-started-at.txt"), encoding: .utf8
            )
            let since = Double(launch.trimmingCharacters(in: .whitespacesAndNewlines)) ?? Date().timeIntervalSince1970
            _ = await SyncEngine.shared.refreshAll()
            try write(["ready": true], name: "refresh-ready.json", directory: directory)
            try await Task.sleep(nanoseconds: 3_000_000_000)
            let cursorBefore = cursor()
            var sequence = [stores()]
            for _ in 0..<3 {
                _ = await SyncEngine.shared.refreshAll()
                sequence.append(stores())
            }
            var modes: [String: Any] = ["directory": stamp(support)]
            for file in try FileManager.default.contentsOfDirectory(at: support, includingPropertiesForKeys: nil) {
                modes[file.lastPathComponent] = stamp(file)
            }
            try write([
                "status": "complete", "refreshes": 3, "stores": sequence,
                "cursorBefore": cursorBefore, "cursorAfter": cursor(), "modes": modes,
                "newHistory": try history(since: since)
            ], name: "refresh-proof.json", directory: directory)
        } catch {
            try? write(["status": "error", "error": error.localizedDescription],
                       name: "refresh-proof.json", directory: directory)
        }
    }

    private static func history(since: TimeInterval) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: support
            .appendingPathComponent("quota-series.json"))) as? [String: Any]
        let formatter = ISO8601DateFormatter()
        let rows = (object?["samples"] as? [[String: Any]] ?? []).filter {
            guard let value = $0["sampledAt"] as? String, let date = formatter.date(from: value) else { return false }
            return date.timeIntervalSince1970 >= since
        }
        let grouped = Dictionary(grouping: rows) { row in
            ["providerID", "accountID", "windowType", "bucketKey"].map { row[$0] as? String ?? "<nil>" }
        }
        let series = grouped.values.map { values -> [String: Any] in
            let ordered = values.sorted { ($0["sampledAt"] as? String ?? "") < ($1["sampledAt"] as? String ?? "") }
            let resets = ordered.compactMap { ($0["resetAt"] as? String).flatMap(formatter.date) }
            return ["provider": values[0]["providerID"] as? String ?? "", "samples": values.count,
                    "accountScoped": values[0]["accountID"] != nil,
                    "backwards": zip(resets, resets.dropFirst()).filter { $0 > $1 }.count]
        }
        return ["samples": rows.count, "series": series]
    }

    private static func delivered() async -> [UNNotification] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getDeliveredNotifications { continuation.resume(returning: $0) }
        }
    }

    private static func settings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { continuation.resume(returning: $0) }
        }
    }

    static func notification(_ directory: URL) async {
        let suite = directory.appendingPathComponent("WP2NotificationProof").path
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let before = Set(await delivered().map { $0.request.identifier })
        let engine = NotificationEngine(userDefaults: defaults)
        let snapshot = ProviderSnapshot(
            providerID: .claudeCode, displayName: "Tokei proof · Claude Code", authStatus: .authenticated,
            quotaWindows: [QuotaWindow(
                providerID: .claudeCode, type: .weekly, used: 75, limit: 100,
                resetAt: Date().addingTimeInterval(12 * 3600), confidence: .providerReported,
                source: "WP-2 notification fixture", bucketKey: "wp2_live_proof", windowDuration: 24 * 3600
            )], todayUsage: .unavailable, weekUsage: .unavailable
        )
        await engine.evaluateThresholds(for: [snapshot])
        await engine.evaluateThresholds(for: [snapshot])
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let notifications = await delivered().filter {
            !before.contains($0.request.identifier) && $0.request.content.body.hasPrefix("Tokei proof · Claude Code")
        }
        let authorization = await settings().authorizationStatus
        try? write([
            "status": "complete", "authorization": String(describing: authorization),
            "delivered": notifications.count, "bodies": notifications.map { $0.request.content.body }
        ], name: "notification-proof.json", directory: directory)
        defaults.removePersistentDomain(forName: suite)
        defaults.synchronize()
        try? FileManager.default.removeItem(atPath: suite + ".plist")
    }
}
#endif

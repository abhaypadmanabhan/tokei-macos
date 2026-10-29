import Foundation

// See the note in MCPServer.swift: set only on this file's copy in the test bundle.
#if TOKEI_CLI_TESTS
import AIUsageDashboardCore
#endif

/// Typed, user-actionable failures for reading the snapshot. Staleness is NOT an
/// error here — a stale snapshot reads successfully and is flagged; only a missing,
/// unreadable, or malformed file fails.
enum SnapshotReadError: Error {
    /// App never launched (or file deleted): the snapshot doesn't exist yet.
    case missing(URL)
    case unreadable(URL, underlying: Error)
    case malformed(URL, underlying: Error)

    /// A clear, non-silent message with the fix, per the issue's failure-behavior spec.
    var message: String {
        switch self {
        case let .missing(url):
            return """
            tokei: no usage snapshot found at \(url.path)
              Launch Tokei at least once so it can write the snapshot, then retry.
              (Tokei writes it after each refresh while running.)
            """
        case let .unreadable(url, underlying):
            return "tokei: could not read \(url.path): \(underlying.localizedDescription)"
        case let .malformed(url, underlying):
            return "tokei: snapshot at \(url.path) is not valid JSON: \(underlying.localizedDescription)"
        }
    }

    var exitCode: Int32 {
        switch self {
        case .missing: return 3
        case .unreadable: return 4
        case .malformed: return 5
        }
    }
}

/// Reads and decodes the public snapshot, stamping reader-side staleness. Clock is
/// injectable so staleness handling is testable.
struct SnapshotReader {
    let fileURL: URL
    let now: () -> Date

    init(
        fileURL: URL = SnapshotReader.defaultFileURL(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.fileURL = fileURL
        self.now = now
    }

    /// The app-support snapshot path, unless `TOKEI_SNAPSHOT_PATH` overrides it — a
    /// hook for tests and for pointing the helper at a non-default location.
    static func defaultFileURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["TOKEI_SNAPSHOT_PATH"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return AgentSnapshot.defaultFileURL()
    }

    /// - Returns: the snapshot with `stale`/`ageSeconds` populated relative to `now`.
    /// - Throws: `SnapshotReadError` with a user-facing message + exit code.
    func read() throws -> AgentSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SnapshotReadError.missing(fileURL)
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw SnapshotReadError.unreadable(fileURL, underlying: error)
        }
        let snapshot: AgentSnapshot
        do {
            snapshot = try AgentSnapshot.makeDecoder().decode(AgentSnapshot.self, from: data)
        } catch {
            throw SnapshotReadError.malformed(fileURL, underlying: error)
        }
        let currentTime = now()
        return snapshot
            .withStaleness(asOf: currentTime)
            .withRecommendationValidity(asOf: currentTime)
    }
}

extension SnapshotReader {
    /// Foundation-only companion to ProviderID; a contract test prevents drift.
    static let providerIDs: Set<String> = [
        "claude_code", "codex", "cursor", "antigravity", "cline", "opencode", "gemini", "copilot"
    ]
}

/// A read-only gate for scripts. Unknown or expired quota always fails closed.
enum GuardCommand {
    struct Options {
        var provider: String?
        var minimumHeadroom: Double = 15
    }

    static func run(arguments: [String], reader: SnapshotReader = SnapshotReader()) -> Int32 {
        guard let options = parse(arguments) else {
            print("tokei guard: invalid arguments; use --provider P and --min-headroom 0...100.")
            return 64
        }
        guard let snapshot = try? reader.read() else {
            print("tokei guard: snapshot unavailable.")
            return 69
        }
        let reading = headroom(snapshot, options: options, now: reader.now())
        guard let headroom = reading.value else {
            print("tokei guard: \(reading.reason).")
            return 69
        }
        let passes = headroom >= options.minimumHeadroom
        let state = passes ? "ready" : "below minimum"
        print("tokei guard: \(state); headroom \(headroom)%, minimum \(options.minimumHeadroom)%.")
        return passes ? 0 : 1
    }

    static func parse(_ arguments: [String]) -> Options? {
        var options = Options()
        var seen: Set<String> = []
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard index + 1 < arguments.count, seen.insert(key).inserted else { return nil }
            let value = arguments[index + 1]
            switch key {
            case "--provider":
                guard SnapshotReader.providerIDs.contains(value) else { return nil }
                options.provider = value
            case "--min-headroom":
                guard let number = Double(value), number.isFinite, (0...100).contains(number) else { return nil }
                options.minimumHeadroom = number
            default: return nil
            }
            index += 2
        }
        return options
    }

    private static func headroom(
        _ snapshot: AgentSnapshot, options: Options, now: Date
    ) -> (value: Double?, reason: String) {
        guard snapshot.stale != true, snapshot.generatedAt <= now.addingTimeInterval(60) else {
            return (nil, "snapshot is stale or timestamped in the future")
        }
        let recommendation = snapshot.recommendation
        if options.provider == nil {
            guard let validUntil = recommendation?.validUntil, validUntil > now else {
                return (nil, "routing recommendation is missing or expired")
            }
        }
        guard let providerID = options.provider ?? recommendation?.target?.provider ?? recommendation?.routeTo,
              let provider = snapshot.providers.first(where: { $0.id == providerID }) else {
            return (nil, "selected provider has no quota reading")
        }
        guard let accounts = provider.accounts, !accounts.isEmpty else {
            return providerHeadroom(provider.windows, now: now)
        }
        let targetID = options.provider == nil
            ? recommendation?.target?.accountID ?? provider.headlineAccountID : nil
        let value = accounts.filter { targetID == nil || $0.accountID == targetID }
            .compactMap { eligibleHeadroom($0, now: now) }.max()
        return (value, "selected account has no fresh eligible quota reading")
    }

    private static func providerHeadroom(_ windows: [AgentWindow], now: Date) -> (value: Double?, reason: String) {
        let limits = windows.filter { $0.bucketKey != "claude_extra_usage" }
        guard !limits.isEmpty else { return (nil, "selected provider has no rate-limit reading") }
        guard limits.allSatisfy({ window in
            guard window.confidence == "official", let observed = window.observedAt,
                  window.usedPercent.isFinite, (0...100).contains(window.usedPercent) else { return false }
            return (-60...AgentSnapshot.stalenessThreshold).contains(now.timeIntervalSince(observed))
                && (window.resetsAt.map { $0 > now } ?? true)
        }), let peak = limits.map(\.usedPercent).max() else {
            return (nil, "selected provider has a stale, expired or unconfirmed reading")
        }
        return (100 - peak, "")
    }

    private static func eligibleHeadroom(_ account: AgentAccount, now: Date) -> Double? {
        guard let quota = account.quota, quota.status == "eligible",
              let validUntil = quota.validUntil, validUntil > now,
              let headroom = quota.headroomPercent, headroom.isFinite, (0...100).contains(headroom),
              let index = quota.bindingWindowIndex, account.windows.indices.contains(index) else { return nil }
        let window = account.windows[index]
        guard window.confidence == "official", let observed = window.observedAt,
              (-60...1_800).contains(now.timeIntervalSince(observed)),
              window.resetsAt.map({ $0 > now }) ?? true else { return nil }
        return headroom
    }
}

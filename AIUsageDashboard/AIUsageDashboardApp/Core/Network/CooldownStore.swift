import Foundation
import os

/// Persists a rate-limit cooldown to disk so a relaunch honours the backoff
/// instead of hammering the endpoint into repeat 429s.
///
/// Shared by the usage clients (Claude / Cursor), which each duplicated the
/// RFC-1123 `Retry-After` parsing, the persist/read round-trip, and the backoff
/// constants verbatim. The on-disk shape (`{ "until": <ISO8601> }`, pretty-printed
/// with sorted keys) is byte-identical to what those clients wrote before this was
/// extracted, so an existing cooldown file keeps loading across the upgrade.
struct CooldownStore: Sendable {
    private let cooldownURL: URL
    private let now: @Sendable () -> Date

    /// Backoff used when a 429 carries no usable `Retry-After`, and (capped by
    /// `maxCooldownInterval`) the ceiling on any persisted cooldown.
    let defaultCooldownInterval: TimeInterval
    let maxCooldownInterval: TimeInterval

    init(
        cooldownURL: URL,
        now: @escaping @Sendable () -> Date,
        defaultCooldownInterval: TimeInterval = 5 * 60,
        maxCooldownInterval: TimeInterval = 60 * 60
    ) {
        self.cooldownURL = cooldownURL
        self.now = now
        self.defaultCooldownInterval = defaultCooldownInterval
        self.maxCooldownInterval = maxCooldownInterval
    }

    /// True when a previously-recorded cooldown has not yet elapsed at `referenceDate`.
    /// A missing or unreadable file reads as "no cooldown" (matching the old `try?`).
    func isActive(at referenceDate: Date) -> Bool {
        guard let cooldown = read() else { return false }
        return cooldown.until > referenceDate
    }

    /// Records a cooldown ending `duration` (clamped to `0...maxCooldownInterval`,
    /// defaulting to `defaultCooldownInterval`) from now, logging rather than
    /// throwing on write failure. A dropped cooldown means repeat 429s across a
    /// relaunch, so the failure is surfaced to the log instead of silently swallowed
    /// (the previous `try?`), but it must never break the fetch that triggered it.
    func record(duration: TimeInterval?) {
        do {
            try persist(duration: duration)
        } catch {
            Self.logger.error(
                "Failed to persist rate-limit cooldown to \(self.cooldownURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Parses an HTTP `Retry-After` header (delay-seconds or an RFC-1123 HTTP-date)
    /// into a non-negative interval measured from `now()`. `nil` when the header is
    /// absent, empty, or unparseable.
    func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty else { return nil }
        if let seconds = TimeInterval(value) {
            return max(0, seconds)
        }
        if let date = Self.httpDateFormatter.date(from: value) {
            return max(0, date.timeIntervalSince(now()))
        }
        return nil
    }

    /// Writes the clamped cooldown. Throws on any filesystem/encoding failure; the
    /// production path goes through `record(duration:)`, which logs the throw.
    func persist(duration: TimeInterval?) throws {
        try FileManager.default.createDirectory(
            at: cooldownURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let interval = min(maxCooldownInterval, max(0, duration ?? defaultCooldownInterval))
        let data = try Self.encoder.encode(Cooldown(until: now().addingTimeInterval(interval)))
        try data.write(to: cooldownURL, options: .atomic)
    }

    /// Reads the persisted cooldown, or `nil` on any missing/corrupt file.
    func read() -> Cooldown? {
        guard let data = try? Data(contentsOf: cooldownURL) else { return nil }
        return try? Self.decoder.decode(Cooldown.self, from: data)
    }

    struct Cooldown: Codable, Equatable {
        let until: Date
    }

    private static let logger = Logger(subsystem: "ai.padzy.tokei", category: "CooldownStore")

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}

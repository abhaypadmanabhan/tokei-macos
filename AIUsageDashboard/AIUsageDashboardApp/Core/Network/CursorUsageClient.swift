import Foundation

public protocol CursorUsageClient: Sendable {
    func fetchUsage(bearerToken: String) async throws -> CursorUsageResponse
}

public struct CursorUsageResponse: Sendable {
    public let quotaWindows: [QuotaWindow]
    public let warnings: [ProviderWarning]

    public init(quotaWindows: [QuotaWindow] = [], warnings: [ProviderWarning] = []) {
        self.quotaWindows = quotaWindows
        self.warnings = warnings
    }
}

public enum CursorUsageError: Error, Sendable {
    case unexpectedResponse
    case httpStatus(Int)
}

public actor CursorUsageClientImpl: CursorUsageClient {
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func fetchUsage(bearerToken: String) async throws -> CursorUsageResponse {
        var request = URLRequest(url: Self.endpointURL)
        // SECURITY: the token leaves the process only as this Bearer header over TLS.
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CursorUsageError.unexpectedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CursorUsageError.httpStatus(httpResponse.statusCode)
        }
        return CursorUsageResponse.decode(data, providerID: .cursor)
    }

    private static let endpointURL = URL(string: "https://api2.cursor.sh/auth/usage")!
}

extension CursorUsageResponse {
    /// Defensive decode: tolerates shape drift by returning a single warning when
    /// no recognizable quota fields are found, never throwing.
    static func decode(_ data: Data, providerID: ProviderID) -> CursorUsageResponse {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return CursorUsageResponse(
                quotaWindows: [],
                warnings: [ProviderWarning(message: "Cursor usage response was not valid JSON.", level: .warning)]
            )
        }

        var windowsMap: [QuotaWindowType: QuotaWindow] = [:]

        // Top-level keys.
        if let window = quotaWindow(from: json, providerID: providerID) {
            windowsMap[window.type] = window
        }

        // Nested quota/usage/subscription objects.
        for nestedKey in ["quota", "usage", "subscription", "premium"] {
            if let nested = json[nestedKey] as? [String: Any],
               let window = quotaWindow(from: nested, providerID: providerID) {
                if windowsMap[window.type] == nil {
                    windowsMap[window.type] = window
                }
            }
        }

        // Array of windows.
        if let windowsArray = json["windows"] as? [[String: Any]] {
            for windowJSON in windowsArray {
                if let window = quotaWindow(from: windowJSON, providerID: providerID, inferType: true) {
                    if windowsMap[window.type] == nil {
                        windowsMap[window.type] = window
                    }
                }
            }
        }

        let windows = windowsMap.values.sorted { $0.type.rawValue < $1.type.rawValue }

        if windows.isEmpty {
            return CursorUsageResponse(
                quotaWindows: [],
                warnings: [ProviderWarning(
                    message: "Cursor usage response did not contain recognized quota fields.",
                    level: .warning
                )]
            )
        }

        return CursorUsageResponse(quotaWindows: windows, warnings: [])
    }

    private static func quotaWindow(
        from json: [String: Any],
        providerID: ProviderID,
        inferType: Bool = false
    ) -> QuotaWindow? {
        guard let used = doubleValue(in: json, keys: ["used", "totalUsed", "consumed", "usage"]) else {
            return nil
        }
        let limit = doubleValue(in: json, keys: ["limit", "quota", "max", "total", "cap"])
        let remaining = doubleValue(in: json, keys: ["remaining", "left", "available", "balance"])
        let resetAt = dateValue(in: json, keys: ["resetAt", "reset", "expiresAt", "periodEnd", "cycleEnd"])
        let type: QuotaWindowType = inferType ? windowType(in: json) : .monthly
        return QuotaWindow(
            providerID: providerID,
            type: type,
            used: used,
            limit: limit,
            remaining: remaining,
            resetAt: resetAt,
            confidence: .providerReported,
            source: "api2.cursor.sh/auth/usage"
        )
    }

    private static func doubleValue(in json: [String: Any], keys: [String]) -> Double? {
        for (key, value) in json where keys.contains(key) {
            if let double = value as? Double { return double }
            if let int = value as? Int { return Double(int) }
            if let string = value as? String, let double = Double(string) { return double }
        }
        return nil
    }

    private static func dateValue(in json: [String: Any], keys: [String]) -> Date? {
        for (key, value) in json where keys.contains(key) {
            if let string = value as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: string) { return date }
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: string) { return date }
            }
            if let timeInterval = value as? TimeInterval {
                return Date(timeIntervalSince1970: timeInterval)
            }
        }
        return nil
    }

    private static func windowType(in json: [String: Any]) -> QuotaWindowType {
        for (key, value) in json where ["type", "window", "period", "range"].contains(key) {
            if let string = value as? String {
                switch string.lowercased() {
                case "session": return .session
                case "daily", "day": return .daily
                case "weekly", "week": return .weekly
                case "monthly", "month": return .monthly
                case "credits": return .credits
                case "lifetime", "total": return .lifetime
                default: break
                }
            }
        }
        return .monthly
    }
}

import XCTest

/// WP-3 addendum 3 (Abhay, 2026-10-29: "remove any sort of eyebrow texts"): no small
/// uppercase, letter-spaced labels anywhere in the app. Scans the `UI/` sources, so a new
/// eyebrow fails here instead of in review. Comments are skipped; anything that must stay
/// goes in an allowlist below with the reason.
final class NoEyebrowTextTests: XCTestCase {
    private static let uiDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("AIUsageDashboardApp/UI")

    /// `file:line` (relative to `UI/`) → why the call may stay.
    private static let allowedCalls: [String: String] = [:]

    /// Literals that are names, not labels.
    private static let allowedWords: Set<String> = [
        "API", "USD", "MTD", "CLI", "MCP", "JSON", "CSV", "UTC", "OAUTH", "HTTP", "HTTPS"
    ]

    private struct SourceLine {
        let location: String
        let code: String
    }

    /// Every non-comment line of every Swift file under `UI/`.
    private static func sourceLines() throws -> [SourceLine] {
        let files = FileManager.default.enumerator(at: uiDirectory, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertGreaterThan(files.count, 20, "the scan must see the UI sources at \(uiDirectory.path)")
        return try files.flatMap { file -> [SourceLine] in
            let relative = file.path.replacingOccurrences(of: uiDirectory.path + "/", with: "")
            return try String(contentsOf: file, encoding: .utf8)
                .components(separatedBy: "\n").enumerated()
                .filter { !$0.element.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .map { SourceLine(location: "\(relative):\($0.offset + 1)", code: $0.element) }
        }
    }

    func testNoUppercasingOrLetterSpacing() throws {
        let banned = [".uppercased()", ".textCase(.uppercase)", ".tracking("]
        let hits = try Self.sourceLines().filter { line in
            banned.contains { line.code.contains($0) } && Self.allowedCalls[line.location] == nil
        }
        let found = hits.map { "\($0.location) \($0.code.trimmingCharacters(in: .whitespaces))" }
        XCTAssertEqual(found, [], "eyebrow styling")
    }

    /// A label typed in capitals ("GOBLIN MODE", "BACK") is the same eyebrow.
    func testNoAllCapsLabels() throws {
        let literal = try NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)
        let interpolation = try NSRegularExpression(pattern: #"\\\([^)]*\)"#)
        var hits: [String] = []
        for line in try Self.sourceLines() {
            let code = line.code as NSString
            for match in literal.matches(in: line.code, range: NSRange(location: 0, length: code.length)) {
                let raw = code.substring(with: match.range(at: 1))
                let text = interpolation.stringByReplacingMatches(
                    in: raw, range: NSRange(location: 0, length: (raw as NSString).length), withTemplate: ""
                )
                if Self.isAllCapsLabel(text) { hits.append("\(line.location) \"\(raw)\"") }
            }
        }
        XCTAssertEqual(hits, [], "labels typed in capitals")
    }

    /// Four or more letters, all of them capitals, and not a hex colour or an allowed name.
    private static func isAllCapsLabel(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        guard letters.count >= 4, letters.allSatisfy(\.isUppercase) else { return false }
        if text.range(of: #"^#?[0-9A-F]{6,8}$"#, options: .regularExpression) != nil { return false }
        let words = text.split(whereSeparator: { !$0.isLetter }).map(String.init)
        return !words.allSatisfy { allowedWords.contains($0) }
    }

    /// The scan itself must catch what it is for.
    func testTheScanCatchesEyebrows() {
        XCTAssertTrue(Self.isAllCapsLabel("GOBLIN MODE"))
        XCTAssertTrue(Self.isAllCapsLabel("FETCHING…"))
        XCTAssertFalse(Self.isAllCapsLabel("Quota windows"))
        XCTAssertFalse(Self.isAllCapsLabel("FF4D4D"), "a hex colour is not a label")
        XCTAssertFalse(Self.isAllCapsLabel("API"))
    }
}

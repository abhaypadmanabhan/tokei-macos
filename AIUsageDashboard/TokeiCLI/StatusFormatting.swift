import Foundation

/// Renders an `AgentSnapshot` as a readable, monospace-friendly table for humans and
/// Bash-capable agents (`tokei status`).
enum StatusFormatting {
    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func table(for snapshot: AgentSnapshot) -> String {
        var lines: [String] = []
        lines.append("Tokei — agent usage snapshot (schema v\(snapshot.schemaVersion))")
        lines.append(headerLine(for: snapshot))
        if let aggregate = snapshot.aggregateUtilizationPercent {
            lines.append("Aggregate utilization: \(percent(aggregate))%")
        } else {
            lines.append("Aggregate utilization: n/a (no provider reported quota)")
        }
        lines.append("")
        lines.append(contentsOf: providerRows(for: snapshot))
        if let recommendation = snapshot.recommendation {
            lines.append("")
            lines.append(contentsOf: recommendationLines(recommendation))
        }
        return lines.joined(separator: "\n")
    }

    /// Freshness line — never silent about staleness (issue §4).
    private static func headerLine(for snapshot: AgentSnapshot) -> String {
        let generated = iso.string(from: snapshot.generatedAt)
        let age = snapshot.ageSeconds.map(humanAge(seconds:)) ?? "unknown age"
        if snapshot.stale == true {
            return "Generated: \(generated)  ⚠︎ STALE — \(age) old; Tokei may not be running"
        }
        return "Generated: \(generated)  (\(age) ago)"
    }

    private static func providerRows(for snapshot: AgentSnapshot) -> [String] {
        let headers = ["PROVIDER", "WINDOW", "USED%", "RESETS", "CONF", "SOURCE"]

        var rows: [[String]] = []
        for provider in snapshot.providers {
            if provider.windows.isEmpty {
                rows.append([provider.displayName, "—", "—", "—", "—", tokensNote(provider)])
            } else {
                for (index, window) in provider.windows.enumerated() {
                    rows.append([
                        index == 0 ? provider.displayName : "",
                        window.type,
                        "\(percent(window.usedPercent))%",
                        window.resetsAt.map(resetColumn(from:)) ?? "—",
                        window.confidence,
                        window.source
                    ])
                }
            }
        }

        if rows.isEmpty { return ["(no providers reported)"] }

        let widths = columnWidths(headers: headers, rows: rows)
        var out = [formatRow(headers, widths: widths)]
        out.append(contentsOf: rows.map { formatRow($0, widths: widths) })
        return out
    }

    private static func recommendationLines(_ recommendation: AgentRecommendation) -> [String] {
        var summary = "Recommendation:"
        if let routeTo = recommendation.routeTo {
            summary += " route to \(routeTo)"
        } else {
            summary += " no clear routing target"
        }
        if !recommendation.avoid.isEmpty {
            summary += "; avoid \(recommendation.avoid.joined(separator: ", "))"
        }
        return [summary, "  \(recommendation.reason)"]
    }

    private static func tokensNote(_ provider: AgentProvider) -> String {
        if let tokens = provider.tokensToday {
            return "no quota window · \(tokens) tok today"
        }
        return "no quota window"
    }

    // MARK: - Column layout

    private static func columnWidths(headers: [String], rows: [[String]]) -> [Int] {
        var widths = headers.map { $0.count }
        for row in rows {
            for (index, cell) in row.enumerated() where index < widths.count {
                widths[index] = max(widths[index], cell.count)
            }
        }
        return widths
    }

    private static func formatRow(_ cells: [String], widths: [Int]) -> String {
        cells.enumerated()
            .map { index, cell in
                let width = index < widths.count ? widths[index] : cell.count
                // Last column isn't padded, to avoid trailing whitespace.
                return index == cells.count - 1 ? cell : cell.padding(toLength: width, withPad: " ", startingAt: 0)
            }
            .joined(separator: "  ")
    }

    // MARK: - Value formatting

    private static func percent(_ value: Double) -> Int { Int(value.rounded()) }

    private static func resetColumn(from date: Date) -> String {
        let delta = date.timeIntervalSinceNow
        guard delta > 0 else { return "now" }
        return AgentSnapshot.compactDuration(delta)
    }

    static func humanAge(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }
}

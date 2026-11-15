import Foundation

#if TOKEI_CLI_TESTS
import AIUsageDashboardCore
#endif

struct RouteOutput: Encodable {
    let generatedAt: Date
    let stale: Bool
    let status: String
    let rows: [AgentRouteRow]
    let unknown: [AgentRouteUnknown]
    let advice: String

    var exitCode: Int32 { status == "ready" ? 0 : status == "exhausted" ? 1 : 69 }
}

enum RouteFormatting {
    static func output(_ snapshot: AgentSnapshot, now: Date, provider: String? = nil) -> RouteOutput {
        let route = snapshot.route
        let stale = snapshot.stale == true || snapshot.isStale(asOf: now)
            || snapshot.generatedAt > now.addingTimeInterval(60)
            || route.map { now.timeIntervalSince($0.generatedAt) > AgentSnapshot.stalenessThreshold
                || $0.generatedAt > now.addingTimeInterval(60) } == true
        var rows: [AgentRouteRow] = []
        var unknown = (route?.unknown ?? []).enumerated().compactMap { index, row -> AgentRouteUnknown? in
            guard SnapshotReader.providerIDs.contains(row.provider), provider == nil || row.provider == provider else { return nil }
            return AgentRouteUnknown(id: "\(row.provider):unknown:\(index)", provider: row.provider,
                                     accountLabel: plainAccount(row.accountLabel), reason: "A fresh, confirmed plan reading is unavailable.")
        }
        for (index, row) in (route?.rows ?? []).enumerated() {
            guard SnapshotReader.providerIDs.contains(row.provider), provider == nil || row.provider == provider else { continue }
            guard !stale, row.validUntil > now, row.resetAt.map({ $0 > now }) ?? true,
                  row.expiringAt.map({ $0 > now }) ?? true,
                  ["session", "fiveHour", "daily", "weekly", "monthly", "perModel"].contains(row.windowType),
                  row.remainingPercent.isFinite, (0...100).contains(row.remainingPercent),
                  ["ready", "avoid"].contains(row.disposition) else {
                unknown.append(AgentRouteUnknown(id: "\(row.provider):expired:\(index)", provider: row.provider,
                                                accountLabel: plainAccount(row.accountLabel), reason: "The saved plan decision has expired."))
                continue
            }
            let disposition = row.remainingPercent <= 15 ? "avoid" : row.disposition
            rows.append(AgentRouteRow(id: "\(row.provider):\(index + 1)", provider: row.provider,
                                      providerName: providerName(row.provider), accountLabel: plainAccount(row.accountLabel),
                                      windowType: row.windowType,
                                      windowLabel: row.windowLabel.flatMap { AgentBurnWindow.isPlainLabel($0) ? $0 : nil },
                                      remainingPercent: row.remainingPercent, resetAt: row.resetAt,
                                      secondsToReset: row.resetAt.map { max(0, $0.timeIntervalSince(now)) },
                                      paceState: row.paceState.flatMap { ["ahead", "onPace", "behind"].contains($0) ? $0 : nil },
                                      disposition: disposition,
                                      reason: AgentBurnWindow.isPlainText(row.reason, maximumLength: 160)
                                        ? row.reason : "Use only the confirmed flat-rate plan capacity.",
                                      validUntil: row.validUntil, expiringAt: row.expiringAt))
        }
        let status: String
        let advice: String
        if let first = rows.first, first.disposition == "ready" {
            status = "ready"
            advice = "Send the next task to \(name(first)). \(first.reason)"
        } else if !rows.isEmpty, unknown.isEmpty {
            status = "exhausted"
            advice = "Avoid these plans until capacity resets."
        } else {
            status = "unavailable"
            if !stale, route != nil, let provider, rows.isEmpty, unknown.isEmpty {
                advice = "\(providerName(provider)) has no flat-rate plan to route to."
            } else {
                advice = stale ? "Plan readings are out of date. Refresh Tokei before routing work."
                    : "No fresh plan recommendation is available. Refresh Tokei before routing work."
            }
        }
        return RouteOutput(generatedAt: route?.generatedAt ?? snapshot.generatedAt, stale: stale,
                           status: status, rows: rows, unknown: unknown, advice: advice)
    }

    static func render(_ output: RouteOutput) -> String {
        var lines = [output.advice]
        for row in output.rows.prefix(8) {
            let reset = row.secondsToReset.map { "resets in \(AgentSnapshot.compactDuration($0))" } ?? "reset unknown"
            let window = row.windowLabel ?? row.windowType
            let pace = row.paceState ?? "pace unknown"
            lines.append("\(name(row)): \(Int(row.remainingPercent.rounded()))% left · \(window) · \(reset) · \(pace) · \(row.disposition)")
        }
        for row in output.unknown.prefix(4) {
            let account = row.accountLabel.map { " (\($0))" } ?? ""
            lines.append("\(providerName(row.provider))\(account): unknown")
        }
        if output.rows.count > 8 || output.unknown.count > 4 { lines.append("Use --json for every plan.") }
        return lines.joined(separator: "\n")
    }

    private static func name(_ row: AgentRouteRow) -> String {
        row.providerName + (row.accountLabel.map { " (\($0))" } ?? "")
    }

    private static func plainAccount(_ label: String?) -> String? {
        label.map { AgentBurnWindow.isPlainLabel($0) && !$0.contains("/") ? $0 : "account" }
    }

    private static func providerName(_ id: String) -> String {
        switch id {
        case "claude_code": return "Claude Code"
        case "codex": return "Codex"
        case "cursor": return "Cursor"
        case "antigravity": return "Antigravity"
        case "cline": return "Cline"
        case "opencode": return "opencode"
        case "gemini": return "Gemini"
        case "copilot": return "Copilot"
        default: return "Unknown agent"
        }
    }
}

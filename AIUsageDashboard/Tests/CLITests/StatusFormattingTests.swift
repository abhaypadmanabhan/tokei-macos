import XCTest
@testable import AIUsageDashboardCore

/// `tokei status` renders for humans *and* for Bash-capable agents, so its table is a
/// consumed surface too (issue #59). The load-bearing assertions here are the two ways a
/// reader can be misled into routing work at a provider that has no usable quota:
///
///  1. a provider with an empty `windows[]` must render as "—", never as 0%;
///  2. a `local_estimate` reading must be visibly labelled and must not be the route target.
///
/// Both encode the `f725bac` rule that absence of data is not headroom.
final class StatusFormattingTests: XCTestCase {

  /// The fixture snapshot, read through `SnapshotReader` so staleness is populated the
  /// same way `tokei status` populates it.
  private func table(
    json: String = AgentSnapshotFixtures.full,
    secondsAfterGeneration: TimeInterval = 60
  ) throws -> String {
    let url = try CLITestSupport.writeSnapshot(json)
    trackForCleanup(url)
    let reader = SnapshotReader(fileURL: url, now: snapshotClock(plus: secondsAfterGeneration))
    return StatusFormatting.table(for: try reader.read())
  }

  private func line(containing needle: String, in table: String,
                    file: StaticString = #filePath, line: UInt = #line) throws -> String {
    let matches = table.split(separator: "\n").filter { $0.contains(needle) }
    XCTAssertEqual(matches.count, 1, "expected exactly one line containing \(needle)", file: file, line: line)
    return try XCTUnwrap(matches.first.map(String.init), file: file, line: line)
  }

  /// Just the provider table. The recommendation's `reason` is prose that legitimately
  /// repeats provider names and percentages, so row assertions must not see it.
  private func rows(of table: String) -> String {
    String(table.split(separator: "\n", omittingEmptySubsequences: false)
      .prefix { !$0.hasPrefix("Recommendation:") }
      .joined(separator: "\n"))
  }

  // MARK: - Untrusted / absent readings (the load-bearing cases)

  /// A provider with no computable window is absent from routing and has no percentage
  /// to show. Rendering it as "0%" would read as "wide open" — the exact misreading that
  /// caused the stale-routing bug.
  func testProviderWithEmptyWindowsNeverRendersAPercentage() throws {
    let output = try table()

    let cursorRow = try line(containing: "Cursor", in: rows(of: output))
    XCTAssertFalse(cursorRow.contains("%"), "empty windows[] must not produce a percentage: \(cursorRow)")
    XCTAssertFalse(cursorRow.contains("0%"))
    XCTAssertTrue(cursorRow.contains("no quota window"), "say why there is no number")
    XCTAssertTrue(cursorRow.contains("1380000 tok today"), "a real token count is still worth showing")
  }

  /// ...and it is not the routing target. The engine (tested in `AgentTests`) is what
  /// guarantees this; the assertion here locks in that the CLI renders that guarantee
  /// rather than inventing a target of its own.
  func testProviderWithEmptyWindowsIsNotTheRouteTarget() throws {
    let output = try table()

    let recommendation = try line(containing: "Recommendation:", in: output)
    XCTAssertTrue(recommendation.contains("route to claude_code"))
    XCTAssertFalse(recommendation.contains("cursor"))
  }

  /// A 0% reading Tokei does not trust must carry its confidence in the row, and must
  /// not be preferred over a trusted 4%.
  func testLocalEstimateProviderIsLabelledAndNotRouted() throws {
    let output = try table()

    let antigravityRow = try line(containing: "Antigravity", in: rows(of: output))
    XCTAssertTrue(antigravityRow.contains("0%"), "it does have a window — the number is shown")
    XCTAssertTrue(antigravityRow.contains("local_estimate"), "…but never without its confidence")
    XCTAssertTrue(antigravityRow.contains("antigravity-local-rpc"), "and its source")

    let recommendation = try line(containing: "Recommendation:", in: output)
    XCTAssertFalse(recommendation.contains("antigravity"), "an untrusted 0% is not free capacity")
  }

  func testAvoidedProviderIsNamed() throws {
    let output = try table()

    let recommendation = try line(containing: "Recommendation:", in: output)
    XCTAssertTrue(recommendation.contains("avoid codex"))
    XCTAssertTrue(
      rows(of: output).contains("\(AgentSnapshotFixtures.codexUsedPercent)%"),
      "the number that earned the avoid is visible in the table"
    )
  }

  /// Guards the fixture itself, not the formatter. `full` hard-codes `avoid: ["codex"]`,
  /// and the engine only avoids at `>= avoidThreshold` — so if Codex's percentage ever
  /// drops below the frozen line, `full` becomes a snapshot production could never emit
  /// and every test reading it starts teaching the wrong rule.
  ///
  /// Read through `AgentRecommendationEngine.policy` rather than off `RouteTargetPolicy`
  /// directly: the fixture is an *agent snapshot*, so the number it must agree with is
  /// whichever tuning the engine that writes those snapshots actually applies. If the
  /// engine is ever pointed at a different tuning, this guard follows it instead of
  /// silently checking a threshold nothing produces.
  func testFixtureAvoidDecisionMatchesTheFrozenThreshold() {
    XCTAssertGreaterThanOrEqual(
      Double(AgentSnapshotFixtures.codexUsedPercent),
      AgentRecommendationEngine.policy.avoidThreshold,
      "fixture avoids codex, so its usedPercent must be at or above the avoid threshold"
    )
  }

  // MARK: - Freshness header

  func testFreshHeaderReportsAgeWithoutAStaleWarning() throws {
    let output = try table(secondsAfterGeneration: 60)

    let header = try line(containing: "Generated:", in: output)
    XCTAssertTrue(header.contains("2026-07-27T12:00:00Z"))
    XCTAssertTrue(header.contains("(1m ago)"))
    XCTAssertFalse(header.contains("STALE"))
  }

  func testStaleHeaderIsLoudAndStatesTheAge() throws {
    let output = try table(secondsAfterGeneration: 7200)

    let header = try line(containing: "Generated:", in: output)
    XCTAssertTrue(header.contains("⚠︎ STALE"))
    XCTAssertTrue(header.contains("2h old"))
    XCTAssertTrue(header.contains("Tokei may not be running"), "say what to do about it")
  }

  // MARK: - Table shape

  func testTableHeaderAndSchemaLine() throws {
    let output = try table()

    XCTAssertTrue(output.hasPrefix("Tokei — agent usage snapshot (schema v1)"))
    let columns = try line(containing: "PROVIDER", in: output)
    XCTAssertEqual(
      columns.split(separator: " ").map(String.init),
      ["PROVIDER", "WINDOW", "USED%", "RESETS", "CONF", "SOURCE"]
    )
  }

  /// A provider's name is printed once; its extra windows continue underneath it. Both
  /// Claude windows must still be visible.
  func testMultiWindowProviderPrintsItsNameOnce() throws {
    let output = try table()

    let claudeRows = rows(of: output).split(separator: "\n").filter { $0.contains("Claude Code") }
    XCTAssertEqual(claudeRows.count, 1)
    XCTAssertTrue(output.contains("fiveHour"))
    XCTAssertTrue(output.contains("weekly"))
    XCTAssertTrue(output.contains("4%"))
    XCTAssertTrue(output.contains("5%"))
  }

  func testAggregateUtilizationIsRendered() throws {
    XCTAssertTrue(
      try table().contains("Aggregate utilization: \(AgentSnapshotFixtures.aggregateUtilizationPercent)%")
    )
  }

  func testFutureResetRendersAsACountdownAndAbsentResetRendersAsADash() throws {
    let output = try table()

    // Three providers report a "weekly" window; pick Claude's by its 5% figure.
    let weeklyRow = try line(containing: "5%", in: rows(of: output))
    XCTAssertTrue(weeklyRow.contains("weekly"))
    XCTAssertTrue(weeklyRow.hasSuffix("oauth_usage_api"), "no trailing padding on the last column")
    // The claude weekly window resets far in the future, so it shows a compact countdown.
    XCTAssertTrue(weeklyRow.contains("h "), "a future reset renders as a countdown: \(weeklyRow)")
    // The antigravity window has no resetsAt at all.
    XCTAssertTrue(try line(containing: "Antigravity", in: output).contains("—"))
  }

  // MARK: - Empty states

  func testEmptySnapshotSaysSoInsteadOfRenderingNothing() throws {
    let output = try table(json: AgentSnapshotFixtures.minimal)

    XCTAssertTrue(output.contains("(no providers reported)"))
    XCTAssertTrue(output.contains("Aggregate utilization: n/a (no provider reported quota)"))
    XCTAssertFalse(output.contains("Recommendation:"), "no recommendation means no line, not an empty one")
  }

  // MARK: - Age formatting

  func testHumanAgeBuckets() {
    XCTAssertEqual(StatusFormatting.humanAge(seconds: 0), "0s")
    XCTAssertEqual(StatusFormatting.humanAge(seconds: 59), "59s")
    XCTAssertEqual(StatusFormatting.humanAge(seconds: 60), "1m")
    XCTAssertEqual(StatusFormatting.humanAge(seconds: 3599), "59m")
    XCTAssertEqual(StatusFormatting.humanAge(seconds: 3600), "1h")
    XCTAssertEqual(StatusFormatting.humanAge(seconds: 86_399), "23h")
    XCTAssertEqual(StatusFormatting.humanAge(seconds: 86_400), "1d")
  }
}

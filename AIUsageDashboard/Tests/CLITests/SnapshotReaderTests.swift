import XCTest
@testable import AIUsageDashboardCore

/// `SnapshotReader` is the single door between the on-disk agent snapshot and every
/// external coding agent (issue #59). It had no coverage at all, which is how a protocol
/// regression shipped once already.
///
/// The staleness assertions here are the `f725bac` trust contract reaching the CLI: a
/// stale read must succeed *and be flagged*, never fail silently and never be served as
/// if it were live.
final class SnapshotReaderTests: XCTestCase {

  // MARK: - Failure modes

  func testMissingSnapshotThrowsMissingWithActionableMessage() {
    let url = CLITestSupport.missingSnapshotURL()
    let reader = SnapshotReader(fileURL: url, now: snapshotClock(plus: 0))

    XCTAssertThrowsError(try reader.read()) { error in
      guard let error = error as? SnapshotReadError, case .missing = error else {
        return XCTFail("expected .missing, got \(error)")
      }
      XCTAssertEqual(error.exitCode, 3)
      XCTAssertTrue(error.message.contains(url.path), "message must name the path it looked at")
      XCTAssertTrue(error.message.contains("Launch Tokei"), "message must state the fix")
    }
  }

  func testMalformedJSONThrowsMalformed() throws {
    let url = try CLITestSupport.writeSnapshot(AgentSnapshotFixtures.malformedJSON)
    trackForCleanup(url)
    let reader = SnapshotReader(fileURL: url, now: snapshotClock(plus: 0))

    XCTAssertThrowsError(try reader.read()) { error in
      guard let error = error as? SnapshotReadError, case .malformed = error else {
        return XCTFail("expected .malformed, got \(error)")
      }
      XCTAssertEqual(error.exitCode, 5)
      XCTAssertTrue(error.message.contains("not valid JSON"))
    }
  }

  /// A directory at the snapshot path exists but cannot be read as a file — the
  /// `.unreadable` branch, distinct from `.missing` and from `.malformed`.
  func testUnreadableSnapshotThrowsUnreadable() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("tokei-cli-unreadable-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    let reader = SnapshotReader(fileURL: directory, now: snapshotClock(plus: 0))

    XCTAssertThrowsError(try reader.read()) { error in
      guard let error = error as? SnapshotReadError, case .unreadable = error else {
        return XCTFail("expected .unreadable, got \(error)")
      }
      XCTAssertEqual(error.exitCode, 4)
    }
  }

  /// Each failure mode gets its own exit code so a shell caller can branch on it.
  func testExitCodesAreDistinct() {
    let url = CLITestSupport.missingSnapshotURL()
    let underlying = CocoaError(.fileReadUnknown)
    let codes = [
      SnapshotReadError.missing(url).exitCode,
      SnapshotReadError.unreadable(url, underlying: underlying).exitCode,
      SnapshotReadError.malformed(url, underlying: underlying).exitCode
    ]
    XCTAssertEqual(Set(codes).count, codes.count, "exit codes must be distinguishable")
  }

  // MARK: - Forward compatibility (frozen contract)

  /// `schemaVersion` stays 1 for anything Tokei writes, but a reader must tolerate a
  /// NEWER file by reading what it understands rather than refusing it outright.
  /// Unknown object fields must not fail decoding either.
  func testNewerSchemaVersionStillDecodes() throws {
    let url = try CLITestSupport.writeSnapshot(AgentSnapshotFixtures.newerSchemaVersion)
    trackForCleanup(url)
    let reader = SnapshotReader(fileURL: url, now: snapshotClock(plus: 0))

    let snapshot = try reader.read()

    XCTAssertEqual(snapshot.schemaVersion, 2, "the file's own version is reported, not ours")
    XCTAssertEqual(snapshot.providers.count, 1)
    XCTAssertEqual(snapshot.providers.first?.windows.first?.usedPercent, 5)
  }

  /// The counterpart: today's writer emits version 1 and it still decodes cleanly.
  func testCurrentSchemaVersionIsOne() throws {
    let url = try CLITestSupport.writeSnapshot(AgentSnapshotFixtures.full)
    trackForCleanup(url)
    let reader = SnapshotReader(fileURL: url, now: snapshotClock(plus: 0))

    XCTAssertEqual(try reader.read().schemaVersion, AgentSnapshot.currentSchemaVersion)
    XCTAssertEqual(AgentSnapshot.currentSchemaVersion, 1, "frozen contract — external agents consume this")
  }

  // MARK: - Staleness (the f725bac contract, reader side)

  func testFreshSnapshotIsNotStaleAndCarriesAge() throws {
    let url = try CLITestSupport.writeSnapshot(AgentSnapshotFixtures.full)
    trackForCleanup(url)
    let reader = SnapshotReader(fileURL: url, now: snapshotClock(plus: 60))

    let snapshot = try reader.read()

    XCTAssertEqual(snapshot.stale, false)
    XCTAssertEqual(snapshot.ageSeconds, 60)
  }

  /// A stale snapshot is NOT an error — it reads successfully and is flagged, so the
  /// caller can warn instead of silently serving old numbers as live ones.
  func testStaleSnapshotReadsSuccessfullyAndSetsStaleFlag() throws {
    let url = try CLITestSupport.writeSnapshot(AgentSnapshotFixtures.full)
    trackForCleanup(url)
    let reader = SnapshotReader(fileURL: url, now: snapshotClock(plus: 7200))

    let snapshot = try reader.read()

    XCTAssertEqual(snapshot.stale, true)
    XCTAssertEqual(snapshot.ageSeconds, 7200)
    XCTAssertEqual(snapshot.providers.count, 4, "the data is still fully readable")
  }

  func testStalenessBoundaryIsExclusive() throws {
    let url = try CLITestSupport.writeSnapshot(AgentSnapshotFixtures.full)
    trackForCleanup(url)
    let threshold = AgentSnapshot.stalenessThreshold

    let atThreshold = SnapshotReader(fileURL: url, now: snapshotClock(plus: threshold))
    let pastThreshold = SnapshotReader(fileURL: url, now: snapshotClock(plus: threshold + 1))

    XCTAssertEqual(try atThreshold.read().stale, false, "exactly at the threshold is still fresh")
    XCTAssertEqual(try pastThreshold.read().stale, true)
  }

  /// Clock skew that puts `generatedAt` in the future must read as age 0, not as
  /// "fresh forever" or a negative age.
  func testFutureGeneratedAtClampsToZeroAge() throws {
    let url = try CLITestSupport.writeSnapshot(AgentSnapshotFixtures.full)
    trackForCleanup(url)
    let reader = SnapshotReader(fileURL: url, now: snapshotClock(plus: -3600))

    let snapshot = try reader.read()

    XCTAssertEqual(snapshot.ageSeconds, 0)
    XCTAssertEqual(snapshot.stale, false)
  }

  // MARK: - Decoding fidelity

  func testDecodesTheFullWireContract() throws {
    let url = try CLITestSupport.writeSnapshot(AgentSnapshotFixtures.full)
    trackForCleanup(url)
    let reader = SnapshotReader(fileURL: url, now: snapshotClock(plus: 60))

    let snapshot = try reader.read()

    XCTAssertEqual(snapshot.generatedAt, AgentSnapshotFixtures.generatedAt)
    XCTAssertEqual(
      snapshot.aggregateUtilizationPercent,
      Double(AgentSnapshotFixtures.aggregateUtilizationPercent)
    )
    XCTAssertEqual(snapshot.providers.map(\.id), ["claude_code", "codex", "cursor", "antigravity"])
    XCTAssertEqual(snapshot.recommendation?.routeTo, "claude_code")
    XCTAssertEqual(snapshot.recommendation?.avoid, ["codex"])

    let claude = try XCTUnwrap(snapshot.providers.first)
    XCTAssertEqual(claude.tokensToday, 277_000_000)
    XCTAssertEqual(claude.windows.map(\.confidence), ["official", "official"])
    XCTAssertNotNil(claude.windows.first?.observedAt, "per-window freshness must survive the round trip")

    // Multi-account Claude (f725bac): `accounts[].id` is what a caller sets
    // CLAUDE_CONFIG_DIR to, so it has to survive decoding intact.
    let accounts = try XCTUnwrap(claude.accounts)
    XCTAssertEqual(accounts.map(\.label), ["default", "account-2"])
    XCTAssertEqual(accounts.first?.id, "/Users/test/.claude")

    // Single-account providers report `accounts` as absent, not empty.
    XCTAssertNil(snapshot.providers[1].accounts)
  }

  func testEmptySnapshotDecodesWithoutRecommendation() throws {
    let url = try CLITestSupport.writeSnapshot(AgentSnapshotFixtures.minimal)
    trackForCleanup(url)
    let reader = SnapshotReader(fileURL: url, now: snapshotClock(plus: 60))

    let snapshot = try reader.read()

    XCTAssertTrue(snapshot.providers.isEmpty)
    XCTAssertNil(snapshot.recommendation)
    XCTAssertNil(snapshot.aggregateUtilizationPercent)
  }
}

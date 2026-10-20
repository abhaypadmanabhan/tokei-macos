import Darwin
import XCTest
@testable import AIUsageDashboardCore

final class CodexRateLimitClientTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let root = URL(fileURLWithPath: "/tmp/codex-fixture")

    private func response(limitID: String = "codex") -> Data {
        Data("""
        {"accountId":"fixture-account","rateLimits":{"limitId":"\(limitID)","planType":"pro",
        "primary":{"usedPercent":42,"windowDurationMins":10080,"resetsAt":1800100000},
        "secondary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":1800009000},
        "credits":{"balance":"25.5","hasCredits":true,"unlimited":false}},
        "rateLimitResetCredits":{"availableCount":2,"credits":[]}}
        """.utf8)
    }

    func testCapturedShapeClassifiesDurationAndHashesIdentity() throws {
        let reading = try CodexRateLimitClient.decode(response(), observedAt: now)
        XCTAssertEqual(reading.accountID, ProviderAccountNormalizer.stableID(
            providerID: .codex, quotaIdentity: "fixture-account"
        ))
        XCTAssertFalse(reading.accountID.contains("fixture-account"))
        XCTAssertEqual(reading.windows.map(\.type), [.weekly, .session, .credits, .credits])
        XCTAssertEqual(reading.windows[0].windowDuration, 604800)
        XCTAssertEqual(reading.windows[1].windowDuration, 18000)
        XCTAssertEqual(reading.windows[0].resetAt, Date(timeIntervalSince1970: 1800100000))
        XCTAssertTrue(reading.windows.allSatisfy { $0.observedAt == now && $0.confidence == .providerReported })
        XCTAssertEqual(reading.windows[2].remaining, 25.5)
        XCTAssertNil(reading.windows[2].used)
        XCTAssertNil(reading.windows[2].limit)
        XCTAssertEqual(reading.windows[3].remaining, 2)
        XCTAssertNil(reading.windows[3].limit)
    }

    func testCapturedCLI163Response() throws {
        let fixture = Data("""
        {
          "ordinaryUsageAllowed": true,
          "rateLimits": {
            "limitId": "codex",
            "limitName": null,
            "normalModelSlug": null,
            "primary": {
              "usedPercent": 1,
              "windowDurationMins": 10080,
              "resetsAt": 1793083660
            },
            "secondary": null,
            "credits": {
              "hasCredits": true,
              "unlimited": false,
              "balance": "62500.0000000000"
            },
            "individualLimit": null,
            "spendControlReached": false,
            "planType": "pro",
            "rateLimitReachedType": null
          },
          "rateLimitsByLimitId": {
            "codex": {
              "limitId": "codex",
              "limitName": null,
              "normalModelSlug": null,
              "primary": {
                "usedPercent": 1,
                "windowDurationMins": 10080,
                "resetsAt": 1793083660
              },
              "secondary": null,
              "credits": {
                "hasCredits": true,
                "unlimited": false,
                "balance": "62500.0000000000"
              },
              "individualLimit": null,
              "spendControlReached": false,
              "planType": "pro",
              "rateLimitReachedType": null
            }
          },
          "rateLimitResetCredits": {
            "availableCount": 3,
            "credits": [
              {
                "status": "available",
                "expiresAt": 1792700657
              },
              {
                "status": "available",
                "expiresAt": 1793299570
              },
              {
                "status": "available",
                "expiresAt": 1794007139
              }
            ]
          },
          "accountId": "fixture-account",
          "rateLimitUpsell": null
        }
        """.utf8)
        let reading = try CodexRateLimitClient.decode(fixture, observedAt: now)
        XCTAssertEqual(reading.windows.first?.type, .weekly)
        XCTAssertEqual(reading.windows.first?.windowDuration, 604800)
        XCTAssertEqual(reading.windows.first?.used, 1)
        XCTAssertEqual(reading.windows.first { $0.bucketKey == "reset_bank" }?.remaining, 3)
        XCTAssertTrue(reading.windows.allSatisfy { $0.observedAt == now })
    }

    func testOnlyCodexLimitCountsAndMapTakesPrecedence() throws {
        XCTAssertTrue(try CodexRateLimitClient.decode(response(limitID: "spark"), observedAt: now).windows.isEmpty)
        let data = Data("""
        {"accountId":"fixture","rateLimits":{"limitId":"spark"},"rateLimitsByLimitId":{
        "codex":{"limitId":"codex","primary":{"usedPercent":8,"windowDurationMins":40320}}}}
        """.utf8)
        let reading = try CodexRateLimitClient.decode(data, observedAt: now)
        XCTAssertEqual(reading.windows.first?.type, .monthly)
        XCTAssertEqual(reading.windows.first?.windowDuration, 28 * 86400)
    }

    func testUnknownDurationAndMissingIdentityFailClosed() throws {
        let data = Data("""
        {"accountId":"fixture","rateLimits":{"limitId":"codex","primary":{"usedPercent":8,"windowDurationMins":900}}}
        """.utf8)
        XCTAssertTrue(try CodexRateLimitClient.decode(data, observedAt: now).windows.isEmpty)
        XCTAssertThrowsError(try CodexRateLimitClient.decode(Data(#"{"rateLimits":{}}"#.utf8), observedAt: now))
    }

    func testInjectedRunnerSuccessGarbageTimeoutAndMissingBinary() async throws {
        let data = response()
        let now = now
        let root = root
        let success = CodexRateLimitClient(resolveBinary: { root }, run: { _, _ in data }, now: { now })
        let reading = try await success.fetch(root: root)
        XCTAssertEqual(reading.windows.first?.used, 42)
        for failure in [CodexRateLimitClient.ProbeError.timeout, .invalidResponse] {
            let client = CodexRateLimitClient(resolveBinary: { root }, run: { _, _ in throw failure })
            do { _ = try await client.fetch(root: root); XCTFail("Expected runner failure") } catch {}
        }
        let garbage = CodexRateLimitClient(resolveBinary: { root }, run: { _, _ in Data("garbage".utf8) })
        do { _ = try await garbage.fetch(root: root); XCTFail("Expected invalid JSON") } catch {}
        let missing = CodexRateLimitClient(resolveBinary: { nil }, run: { _, _ in
            XCTFail("Must not launch without a binary")
            return data
        })
        do { _ = try await missing.fetch(root: root); XCTFail("Expected missing binary") } catch {
            XCTAssertEqual(error as? CodexRateLimitClient.ProbeError, .missingBinary)
        }
    }

    private func script(_ body: String, in directory: URL) throws -> URL {
        let binary = directory.appendingPathComponent("codex")
        try Data(("#!/bin/sh\n" + body).utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        return binary
    }

    func testRealRunnerHandshakeNotificationAndShutdown() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = try script("""
        read -r initialize
        case "$initialize" in *initialize*) ;; *) exit 1 ;; esac
        printf '%s\\n' '{"id":1,"result":{}}'
        read -r initialized
        read -r limits
        case "$initialized" in *initialized*) ;; *) exit 2 ;; esac
        case "$limits" in *account*rateLimits*read*) ;; *) exit 3 ;; esac
        printf '%s\\n' '{"method":"notification"}'
        printf '%s' '{"id":2,"result":{"accountId":"fixture","rateLimits":{"limitId":"codex",'
        printf '%s\\n' '"primary":{"usedPercent":10,"windowDurationMins":300}}}}'
        while :; do :; done
        """, in: directory)
        let result = try CodexRateLimitClient.runProcess(binary: binary, root: directory)
        XCTAssertEqual(try CodexRateLimitClient.decode(result, observedAt: now).windows.first?.used, 10)
    }

    func testRealRunnerTimeoutKillsChildWithPartialFrame() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = try script("""
        printf '%s' "$$" > "$CODEX_HOME/pid"
        printf '{"id":1'
        while :; do :; done
        """, in: directory)
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try CodexRateLimitClient.runProcess(binary: binary, root: directory, timeout: 0.2)) {
            XCTAssertEqual($0 as? CodexRateLimitClient.ProbeError, .timeout)
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 1)
        let pid = try XCTUnwrap(Int32(String(contentsOf: directory.appendingPathComponent("pid"))))
        for _ in 0..<100 where Darwin.kill(pid, 0) == 0 { usleep(1000) }
        XCTAssertEqual(Darwin.kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    func testRealRunnerRejectsUnboundedOutput() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = try script(
            "while :; do printf 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'; done", in: directory
        )
        XCTAssertThrowsError(try CodexRateLimitClient.runProcess(binary: binary, root: directory)) {
            XCTAssertEqual($0 as? CodexRateLimitClient.ProbeError, .oversizedOutput)
        }
    }

    func testKnownPathsResolveNewestVersionWithoutShell() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        for version in ["v22.9.0", "v22.10.0"] {
            let binary = home.appendingPathComponent(".nvm/versions/node/\(version)/bin/codex")
            try FileManager.default.createDirectory(
                at: binary.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data("fixture".utf8).write(to: binary)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        }
        let global = home.appendingPathComponent("global/codex")
        try FileManager.default.createDirectory(
            at: global.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("older CLI".utf8).write(to: global)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: global.path)
        let binary = try XCTUnwrap(CodexRateLimitClient.resolveBinary(
            home: home, systemPaths: [global.deletingLastPathComponent().path]
        ))
        XCTAssertTrue(binary.path.contains("v22.10.0"))
    }
}

extension CodexRateLimitClientTests {
    func testEarlyStdinCloseFailsWithoutSIGPIPE() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = try script("""
        read -r initialize
        exec 0<&-
        printf '%s\\n' '{"id":1,"result":{}}'
        exit 0
        """, in: directory)
        let previous = Darwin.signal(SIGPIPE, SIG_DFL)
        defer { Darwin.signal(SIGPIPE, previous) }
        XCTAssertThrowsError(try CodexRateLimitClient.runProcess(binary: binary, root: directory))
    }

    func testTimeoutKillsWrapperAndGrandchild() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = try script("""
        printf '%s' "$$" > "$CODEX_HOME/pid"
        sleep 60 &
        printf '%s' "$!" > "$CODEX_HOME/grandchild"
        wait
        """, in: directory)
        defer {
            for name in ["pid", "grandchild"] {
                if let value = try? String(contentsOf: directory.appendingPathComponent(name)), let pid = Int32(value) {
                    Darwin.kill(pid, SIGKILL)
                }
            }
        }
        XCTAssertThrowsError(try CodexRateLimitClient.runProcess(binary: binary, root: directory, timeout: 0.2))
        for name in ["pid", "grandchild"] {
            let pid = try XCTUnwrap(Int32(String(contentsOf: directory.appendingPathComponent(name))))
            for _ in 0..<100 where Darwin.kill(pid, 0) == 0 { usleep(1000) }
            XCTAssertEqual(Darwin.kill(pid, 0), -1, "Surviving \(name)")
            XCTAssertEqual(errno, ESRCH)
        }
    }
}

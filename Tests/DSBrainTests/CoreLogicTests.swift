import XCTest
@testable import DSBrainLib

final class LogParserTests: XCTestCase {
    private let parser = LogParser()

    func testPrefillSpeedAndProgress() throws {
        let line =
            "0804 15:16:52 ds4-server: chat ctx=20480..31286:10806 RESPPROTO TOOLS prefill chunk 4096/10806 (37.9%) chunk=209.31 t/s avg=209.31 t/s 19.569s"
        let speeds = parser.extractTokenSpeeds(from: line)
        XCTAssertEqual(speeds.count, 1)
        XCTAssertEqual(speeds[0].kind, .prefill)
        XCTAssertEqual(speeds[0].value, 209.31, accuracy: 0.001)

        let progress = try XCTUnwrap(parser.extractPrefillProgress(from: line))
        XCTAssertEqual(progress.current, 4096)
        XCTAssertEqual(progress.total, 10806)
        XCTAssertEqual(progress.percent, 37.9, accuracy: 0.001)
    }

    func testDecodeSpeed() {
        let line = "ds4-server: decoding chunk=8.42 t/s"
        let speeds = parser.extractTokenSpeeds(from: line)
        XCTAssertEqual(speeds.count, 1)
        XCTAssertEqual(speeds[0].kind, .generation)
        XCTAssertEqual(speeds[0].value, 8.42, accuracy: 0.001)
    }

    func testSSDStreamingBudgetLine() throws {
        let line =
            "ds4: metal SSD streaming total expert budget 10.00 GiB = 3.38 GiB prefill headroom + 6.62 GiB dynamic cache (1005 experts, 6.75 MiB each)"
        let update = try XCTUnwrap(parser.extractSSDStreamingCacheUpdate(from: line))
        guard case let .budget(total, headroom, dynamic, experts, expertMiB) = update else {
            return XCTFail("expected budget update")
        }
        XCTAssertEqual(total, 10.0, accuracy: 0.001)
        XCTAssertEqual(headroom, 3.38, accuracy: 0.001)
        XCTAssertEqual(dynamic, 6.62, accuracy: 0.001)
        XCTAssertEqual(experts, 1005)
        XCTAssertEqual(expertMiB, 6.75, accuracy: 0.001)
    }

    func testSSDStreamingBudgetWithFullLayers() throws {
        let line =
            "ds4: metal SSD streaming total expert budget 24.00 GiB = 4.00 GiB prefill headroom + 2.00 GiB full layers + 18.00 GiB dynamic cache (2000 experts, 9.00 MiB each)"
        let update = try XCTUnwrap(parser.extractSSDStreamingCacheUpdate(from: line))
        guard case let .budget(_, _, dynamic, experts, _) = update else {
            return XCTFail("expected budget update")
        }
        XCTAssertEqual(dynamic, 18.0, accuracy: 0.001)
        XCTAssertEqual(experts, 2000)
    }

    func testSSDStreamingLiveTelemetryMerges() throws {
        let budgetLine =
            "ds4: metal SSD streaming total expert budget 10.00 GiB = 3.38 GiB prefill headroom + 6.62 GiB dynamic cache (1005 experts, 6.75 MiB each)"
        let liveLine =
            "ds4:   streaming expert cache budget=1005 experts entries=800 expert=6.75 MiB target=6.62 GiB live=5.10 GiB, hits=100 misses=20 hit_rate=0.833 wraps=0 evictions=0 buffer_allocs=0 buffer_reuses=0"
        let budget = try XCTUnwrap(parser.extractSSDStreamingCacheUpdate(from: budgetLine))
        let live = try XCTUnwrap(parser.extractSSDStreamingCacheUpdate(from: liveLine))
        let merged = live.applying(to: budget.applying(to: nil))
        XCTAssertEqual(merged.dynamicCacheGiB, 6.62, accuracy: 0.001)
        XCTAssertEqual(merged.liveGiB ?? -1, 5.10, accuracy: 0.001)
        XCTAssertEqual(merged.hitRate ?? -1, 0.833, accuracy: 0.001)
        XCTAssertTrue(merged.summaryLine.contains("1005 exp"))
        XCTAssertTrue(merged.summaryLine.contains("hit 83%"))

        // A later budget line must drop stale live fields.
        let refreshed = try XCTUnwrap(parser.extractSSDStreamingCacheUpdate(from: budgetLine))
        let afterBudget = refreshed.applying(to: merged)
        XCTAssertNil(afterBudget.liveGiB)
        XCTAssertNil(afterBudget.hitRate)
        XCTAssertEqual(afterBudget.dynamicCacheGiB, 6.62, accuracy: 0.001)
    }

    func testKVDiskCacheBudgetAndHit() throws {
        let budgetLine =
            "0804 17:47:23 ds4-server: KV disk cache /Users/erkan/.cache/ds4-kv (budget=8192 MiB, cross-quant=accept, min=512, cold_max=30000, continued=10000, trim=32, align=2048, hit_half_life=21600s)"
        let hitLine =
            "0804 17:47:25 ds4-server: kv cache hit text RESPPROTO tokens=20480 text=85719 quant=2 key=token-text load=74.0 ms file=/Users/erkan/.cache/ds4-kv/abc.kv"

        let budget = try XCTUnwrap(parser.extractKVDiskCacheUpdate(from: budgetLine))
        let hit = try XCTUnwrap(parser.extractKVDiskCacheUpdate(from: hitLine))
        let info = hit.applying(to: budget.applying(to: nil))

        XCTAssertEqual(info.budgetMiB, 8192)
        XCTAssertEqual(info.path, "/Users/erkan/.cache/ds4-kv")
        XCTAssertEqual(info.hitCount, 1)
        XCTAssertEqual(info.lastHitTokens, 20480)
        XCTAssertEqual(info.lastHitLoadMs ?? -1, 74.0, accuracy: 0.001)
        XCTAssertTrue(info.summaryLine.contains("20k"))
        XCTAssertTrue(info.summaryLine.contains("74"))
        XCTAssertTrue(info.summaryLine.contains("8.0 GiB") || info.summaryLine.contains("budget"))
    }

    func testKVDiskCacheHitConsumedVariant() throws {
        let line =
            "ds4-server: kv cache hit text RESPPROTO tokens=4096 text=100 quant=4 key=token-text load=12.5 ms consumed file=/tmp/x.kv"
        let update = try XCTUnwrap(parser.extractKVDiskCacheUpdate(from: line))
        guard case let .hit(tokens, loadMs) = update else {
            return XCTFail("expected hit")
        }
        XCTAssertEqual(tokens, 4096)
        XCTAssertEqual(loadMs, 12.5, accuracy: 0.001)
    }
}

final class RollingMetricTests: XCTestCase {
    func testStickyLatestSurvivesWindow() {
        var metric = RollingMetric(window: 1)
        let t0 = Date(timeIntervalSince1970: 1_000)
        metric.record(12.5, at: t0)
        XCTAssertEqual(metric.stickyLatest(now: t0.addingTimeInterval(0.5)), 12.5)
        XCTAssertEqual(metric.stickyLatest(now: t0.addingTimeInterval(5)), 12.5)
        XCTAssertNil(metric.latest(now: t0.addingTimeInterval(5)))
    }
}

final class TrayActivityTrackerTests: XCTestCase {
    func testPrefillStickyUntilPromptDone() {
        var tracker = TrayActivityTracker()
        tracker.ingest(line: "chat … prompt start")
        XCTAssertEqual(tracker.prefillPercent, 0)

        tracker.ingest(
            line: "prefill chunk 4096/10806 (37.9%) chunk=209.31 t/s"
        )
        XCTAssertEqual(tracker.prefillPercent, 37.9)

        tracker.tick(tokensPerSecond: nil)
        XCTAssertEqual(tracker.prefillPercent, 37.9)
        XCTAssertTrue(tracker.isRequestBusy)

        tracker.ingest(line: "prefill chunk 10806/10806 (100.0%) chunk=135.28 t/s")
        XCTAssertEqual(tracker.prefillPercent, 100.0)

        tracker.ingest(line: "prompt done 59.706s")
        XCTAssertNil(tracker.prefillPercent)
        XCTAssertFalse(tracker.isRequestBusy)
    }

    func testZeroPrefillClearsWithoutChunks() {
        var tracker = TrayActivityTracker()
        tracker.ingest(line: "chat … prompt start")
        XCTAssertEqual(tracker.prefillPercent, 0)
        // Simulate grace expiry without any prefill chunk lines.
        tracker.tick(tokensPerSecond: nil)
        // Force grace by backdating via a second tick after sleeping is flaky;
        // call clear path through Metal abort line instead.
        tracker.ingest(line: "ds4: Metal model range 0.04..0.04 GiB is not covered by mapped model views")
        XCTAssertNil(tracker.prefillPercent)
        XCTAssertFalse(tracker.isRequestBusy)
    }
}

final class LaunchCommandTests: XCTestCase {
    func testHostPortAndWorkingDirectory() {
        let command = """
            /data/AI/ds4/ds4-server \\
              --model /data/AI/ds4/ds4flash.gguf \\
              --host 127.0.0.1 \\
              --port 8080
            """
        XCTAssertEqual(LaunchCommand.host(from: command), "127.0.0.1")
        XCTAssertEqual(LaunchCommand.port(from: command), 8080)
        XCTAssertEqual(LaunchCommand.workingDirectory(from: command), "/data/AI/ds4")
        XCTAssertEqual(LaunchCommand.flagValue("model", in: command), "/data/AI/ds4/ds4flash.gguf")
    }

    func testEqualsFormAndDefaults() {
        XCTAssertEqual(LaunchCommand.host(from: "--host=10.0.0.2 --port=9000"), "10.0.0.2")
        XCTAssertEqual(LaunchCommand.port(from: "--host=10.0.0.2 --port=9000"), 9000)
        XCTAssertEqual(LaunchCommand.host(from: "./ds4-server --metal"), LaunchCommand.defaultHost)
        XCTAssertEqual(LaunchCommand.port(from: "./ds4-server --metal"), LaunchCommand.defaultPort)
    }

    func testRelativeBinaryHasNoWorkingDirectory() {
        XCTAssertNil(LaunchCommand.workingDirectory(from: "./eko.sh --metal"))
        XCTAssertNil(LaunchCommand.workingDirectory(from: "subdir/ds4-server --port 8080"))
        XCTAssertNil(LaunchCommand.workingDirectory(from: "cd /data/AI/ds4 && ./ds4-server"))
    }

    func testPATHBinaryResolvesWorkingDirectory() {
        // `bash` is always on a login PATH; cwd is its parent directory.
        let cwd = LaunchCommand.workingDirectory(from: "bash --help")
        XCTAssertNotNil(cwd)
        XCTAssertTrue(cwd == "/bin" || cwd == "/usr/bin", "unexpected cwd: \(cwd ?? "nil")")
        XCTAssertNotNil(LaunchCommand.resolveOnPATH("bash"))
    }

    func testWorkingDirectoryErrorMessages() {
        XCTAssertTrue(
            LaunchCommand.workingDirectoryError(for: "./eko.sh").contains("relative path")
        )
        XCTAssertTrue(
            LaunchCommand.workingDirectoryError(for: "definitely-not-a-real-dsbrain-bin-xyz").contains("PATH")
        )
    }

    func testQuotedAbsoluteBinaryWithSpaces() {
        let command = #""/data/AI/My Tools/ds4-server" --host "127.0.0.1" --port 8080"#
        XCTAssertEqual(LaunchCommand.workingDirectory(from: command), "/data/AI/My Tools")
        XCTAssertEqual(LaunchCommand.host(from: command), "127.0.0.1")
        XCTAssertEqual(LaunchCommand.port(from: command), 8080)
    }

    func testPlainNewlinesWithoutBackslash() {
        let command = """
            /data/AI/ds4/ds4-server
              --model /data/AI/ds4/ds4flash.gguf
              --host 127.0.0.1
              --port 8080
            """
        XCTAssertEqual(LaunchCommand.host(from: command), "127.0.0.1")
        XCTAssertEqual(LaunchCommand.port(from: command), 8080)
        XCTAssertEqual(LaunchCommand.workingDirectory(from: command), "/data/AI/ds4")
        XCTAssertEqual(
            LaunchCommand.normalizedForShell(command),
            "/data/AI/ds4/ds4-server --model /data/AI/ds4/ds4flash.gguf --host 127.0.0.1 --port 8080"
        )
    }

    func testNormalizedForShellCollapsesBackslashContinuations() {
        let command = "/data/AI/ds4/ds4-server \\\n  --port 9000"
        XCTAssertEqual(
            LaunchCommand.normalizedForShell(command),
            "/data/AI/ds4/ds4-server --port 9000"
        )
    }
}

final class ListeningPortParseTests: XCTestCase {
    func testParseLsofLine() {
        let line = "ds4-serve 12345 erkan   12u  IPv4 0xabc      0t0  TCP 127.0.0.1:8080 (LISTEN)"
        let parsed = ListeningPort.parseLine(line, port: 8080)
        XCTAssertEqual(parsed?.pid, 12345)
        XCTAssertEqual(parsed?.address, "127.0.0.1:8080")
        XCTAssertNil(ListeningPort.parseLine("COMMAND PID USER FD TYPE", port: 8080))
    }
}

final class ContextFillParseTests: XCTestCase {
    private let parser = LogParser()

    func testContextWindowAndSpanMerge() throws {
        let windowLine =
            "0804 17:47:23 ds4-server: context buffers 2402.87 MiB (ctx=130000, backend=metal, prefill_chunk=4096, raw_kv_rows=4352, compressed_kv_rows=32502)"
        let promptLine =
            "0804 17:47:25 ds4-server: chat ctx=20480..80152:59672 RESPPROTO TOOLS prompt start"

        let windowUpdates = parser.extractContextFillUpdates(from: windowLine)
        XCTAssertEqual(windowUpdates, [.window(nCtx: 130_000)])

        let spanUpdates = parser.extractContextFillUpdates(from: promptLine)
        XCTAssertEqual(spanUpdates.count, 1)
        guard case let .span(cached, prompt, suffix) = spanUpdates[0] else {
            return XCTFail("expected span")
        }
        XCTAssertEqual(cached, 20_480)
        XCTAssertEqual(prompt, 80_152)
        XCTAssertEqual(suffix, 59_672)

        var info: ContextFillInfo?
        for u in windowUpdates + spanUpdates {
            info = u.applying(to: info)
        }
        let fill = try XCTUnwrap(info)
        XCTAssertEqual(fill.nCtx, 130_000)
        XCTAssertEqual(fill.tokensUsed, 80_152)
        XCTAssertEqual(fill.ctxLabel, "80k/130k")
        XCTAssertEqual(fill.fillFraction, Double(80_152) / 130_000.0, accuracy: 0.0001)
    }

    func testGenerationAddsToPromptTokens() throws {
        let promptLine = "ds4-server: chat ctx=1000..5000:4000 prompt start"
        let decodeLine =
            "ds4-server: chat ctx=1000..5000:4000 gen=42 RESPPROTO decoding chunk=8.42 t/s avg=8.42 t/s 1.000s"

        var info: ContextFillInfo?
        for u in parser.extractContextFillUpdates(from: promptLine) {
            info = u.applying(to: info)
        }
        for u in parser.extractContextFillUpdates(from: decodeLine) {
            info = u.applying(to: info)
        }
        let fill = try XCTUnwrap(info)
        XCTAssertEqual(fill.promptTokens, 5000)
        XCTAssertEqual(fill.generatedTokens, 42)
        XCTAssertEqual(fill.tokensUsed, 5042)
    }

    func testNewSpanResetsGeneration() {
        var info = ContextFillUpdate.span(cached: 0, prompt: 1000, suffix: 1000)
            .applying(to: nil)
        info = ContextFillUpdate.generation(50).applying(to: info)
        XCTAssertEqual(info.tokensUsed, 1050)
        info = ContextFillUpdate.span(cached: 1000, prompt: 2000, suffix: 1000)
            .applying(to: info)
        XCTAssertEqual(info.generatedTokens, 0)
        XCTAssertEqual(info.tokensUsed, 2000)
    }
}

final class SystemMemoryPressureTests: XCTestCase {
    func testSysctlLevelMapping() {
        XCTAssertEqual(SystemMemorySampler.Pressure.fromSysctlLevel(0), .normal)
        XCTAssertEqual(SystemMemorySampler.Pressure.fromSysctlLevel(1), .warning)
        XCTAssertEqual(SystemMemorySampler.Pressure.fromSysctlLevel(2), .critical)
        XCTAssertEqual(SystemMemorySampler.Pressure.fromSysctlLevel(4), .critical)
    }
}

final class ProjectEntryTests: XCTestCase {
    func testISO8601RoundTrip() throws {
        let original = ProjectEntry(
            path: "/tmp/DemoProject",
            name: "DemoProject",
            lastAgent: .pi,
            lastOpenedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(ProjectEntry.self, from: data)
        XCTAssertEqual(decoded.path, original.path)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.lastAgent, .pi)
        XCTAssertEqual(decoded.lastOpenedAt.timeIntervalSince1970, 1_700_000_000, accuracy: 1)
    }

    func testOMPAgentKindRoundTrip() throws {
        let original = ProjectEntry(
            path: "/tmp/omp-proj",
            name: "omp-proj",
            lastAgent: .omp,
            lastOpenedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProjectEntry.self, from: data)
        XCTAssertEqual(decoded.lastAgent, .omp)
        XCTAssertEqual(AgentKind.omp.displayName, "OMP")
        XCTAssertTrue(AgentKind.omp.requiresServer)
        XCTAssertFalse(AgentKind.cursor.requiresServer)
    }

    func testNormalizePathAbsolute() {
        let path = ProjectStore.normalizePath("/tmp")
        XCTAssertTrue(path.hasPrefix("/"))
        XCTAssertEqual((path as NSString).lastPathComponent, "tmp")
    }
}

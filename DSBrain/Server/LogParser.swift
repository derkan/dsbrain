import Foundation

enum TokenSpeedKind: Equatable {
    case prefill
    case generation
}

struct TokenSpeedSample {
    let kind: TokenSpeedKind
    let value: Double
}

struct PrefillProgress {
    let current: Int
    let total: Int
    let percent: Double
}

/// SSD streaming expert-cache sizing from ds4-server logs (auto or explicit budget).
struct SSDStreamingCacheInfo: Equatable {
    var totalBudgetGiB: Double
    var prefillHeadroomGiB: Double
    var dynamicCacheGiB: Double
    var expertCount: Int
    var expertMiB: Double
    var liveGiB: Double?
    var targetGiB: Double?
    var hitRate: Double?

    var summaryLine: String {
        var parts: [String] = [
            String(format: "%.2f GiB dyn", dynamicCacheGiB),
            "\(expertCount) exp",
        ]
        if let liveGiB {
            parts.append(String(format: "live %.2f", liveGiB))
        }
        if let hitRate {
            parts.append(String(format: "hit %.0f%%", hitRate * 100))
        }
        return "SSD cache: " + parts.joined(separator: " · ")
    }
}

/// KV disk-cache status from ds4-server logs (budget line + hit lines).
struct KVDiskCacheInfo: Equatable {
    var budgetMiB: UInt64?
    var path: String?
    var hitCount: Int = 0
    var lastHitTokens: Int?
    var lastHitLoadMs: Double?

    var summaryLine: String {
        var parts: [String] = []
        if let tokens = lastHitTokens, let ms = lastHitLoadMs {
            parts.append("last \(Self.formatTokens(tokens)) · \(Self.formatMs(ms))")
        }
        if hitCount > 0 {
            parts.append(hitCount == 1 ? "1 hit" : "\(hitCount) hits")
        }
        if let budgetMiB {
            if budgetMiB >= 1024 {
                parts.append(String(format: "budget %.1f GiB", Double(budgetMiB) / 1024.0))
            } else {
                parts.append("budget \(budgetMiB) MiB")
            }
        }
        if parts.isEmpty {
            return "KV cache: enabled"
        }
        return "KV cache: " + parts.joined(separator: " · ")
    }

    private static func formatTokens(_ n: Int) -> String {
        if n >= 1000 {
            let k = Double(n) / 1000.0
            if k >= 10 || abs(k - k.rounded()) < 0.05 {
                return "\(Int(k.rounded()))k"
            }
            return String(format: "%.1fk", k)
        }
        return "\(n)"
    }

    private static func formatMs(_ ms: Double) -> String {
        if ms >= 100 {
            return String(format: "%.0fms", ms)
        }
        return String(format: "%.1fms", ms)
    }
}

enum KVDiskCacheUpdate: Equatable {
    case budget(path: String, budgetMiB: UInt64)
    case hit(tokens: Int, loadMs: Double)

    func applying(to existing: KVDiskCacheInfo?) -> KVDiskCacheInfo {
        switch self {
        case let .budget(path, budgetMiB):
            var info = existing ?? KVDiskCacheInfo()
            info.path = path
            info.budgetMiB = budgetMiB
            return info
        case let .hit(tokens, loadMs):
            var info = existing ?? KVDiskCacheInfo()
            info.hitCount += 1
            info.lastHitTokens = tokens
            info.lastHitLoadMs = loadMs
            return info
        }
    }
}

/// Context window fill from ds4-server logs (`context buffers` + `ctx=A..B:C` + `gen=N`).
struct ContextFillInfo: Equatable {
    var nCtx: Int?
    /// Prompt end position (middle number in `cached..prompt:suffix`).
    var promptTokens: Int?
    /// Generated tokens from `gen=N` on decode/finish lines.
    var generatedTokens: Int?

    var tokensUsed: Int {
        (promptTokens ?? 0) + (generatedTokens ?? 0)
    }

    var ctxLabel: String {
        let used = Self.formatTokens(tokensUsed)
        guard let nCtx else { return "\(used)/—" }
        return "\(used)/\(Self.formatTokens(nCtx))"
    }

    var fillFraction: Double {
        guard let nCtx, nCtx > 0 else { return 0 }
        return min(max(Double(tokensUsed) / Double(nCtx), 0), 1)
    }

    static func formatTokens(_ n: Int) -> String {
        if n >= 1000 {
            let k = Double(n) / 1000.0
            if k >= 10 || abs(k - k.rounded()) < 0.05 {
                return "\(Int(k.rounded()))k"
            }
            return String(format: "%.1fk", k)
        }
        return "\(n)"
    }
}

enum ContextFillUpdate: Equatable {
    case window(nCtx: Int)
    case span(cached: Int, prompt: Int, suffix: Int)
    case generation(Int)

    func applying(to existing: ContextFillInfo?) -> ContextFillInfo {
        switch self {
        case let .window(nCtx):
            var info = existing ?? ContextFillInfo()
            info.nCtx = nCtx
            return info
        case let .span(_, prompt, _):
            var info = existing ?? ContextFillInfo()
            info.promptTokens = prompt
            info.generatedTokens = 0
            return info
        case let .generation(gen):
            var info = existing ?? ContextFillInfo()
            info.generatedTokens = gen
            return info
        }
    }
}

enum SSDStreamingCacheUpdate: Equatable {
    case budget(
        totalGiB: Double,
        headroomGiB: Double,
        dynamicGiB: Double,
        experts: Int,
        expertMiB: Double
    )
    case live(
        experts: Int,
        expertMiB: Double,
        targetGiB: Double,
        liveGiB: Double,
        hitRate: Double
    )

    func applying(to existing: SSDStreamingCacheInfo?) -> SSDStreamingCacheInfo {
        switch self {
        case let .budget(total, headroom, dynamic, experts, expertMiB):
            var info = existing ?? SSDStreamingCacheInfo(
                totalBudgetGiB: total,
                prefillHeadroomGiB: headroom,
                dynamicCacheGiB: dynamic,
                expertCount: experts,
                expertMiB: expertMiB
            )
            info.totalBudgetGiB = total
            info.prefillHeadroomGiB = headroom
            info.dynamicCacheGiB = dynamic
            info.expertCount = experts
            info.expertMiB = expertMiB
            // Fresh budget line replaces prior live telemetry.
            info.liveGiB = nil
            info.targetGiB = nil
            info.hitRate = nil
            return info
        case let .live(experts, expertMiB, target, live, hitRate):
            var info = existing ?? SSDStreamingCacheInfo(
                totalBudgetGiB: target,
                prefillHeadroomGiB: 0,
                dynamicCacheGiB: target,
                expertCount: experts,
                expertMiB: expertMiB
            )
            info.expertCount = experts
            info.expertMiB = expertMiB
            info.targetGiB = target
            info.liveGiB = live
            info.hitRate = hitRate
            return info
        }
    }
}

final class LogParser {
    private let prefillChunkRegex: NSRegularExpression
    private let decodeChunkRegex: NSRegularExpression
    private let prefillPercentRegex: NSRegularExpression
    private let ssdBudgetRegex: NSRegularExpression
    private let ssdLiveRegex: NSRegularExpression
    private let kvBudgetRegex: NSRegularExpression
    private let kvHitRegex: NSRegularExpression
    private let contextWindowRegex: NSRegularExpression
    private let contextSpanRegex: NSRegularExpression
    private let generationTokensRegex: NSRegularExpression

    init() {
        prefillChunkRegex = try! NSRegularExpression(
            pattern: #"prefill chunk \d+/\d+ \([\d.]+%\) chunk=([\d.]+) t/s"#,
            options: [.caseInsensitive]
        )
        decodeChunkRegex = try! NSRegularExpression(
            pattern: #"decoding chunk=([\d.]+) t/s"#,
            options: [.caseInsensitive]
        )
        prefillPercentRegex = try! NSRegularExpression(
            pattern: #"prefill chunk (\d+)/(\d+) \(([\d.]+)%\)"#,
            options: [.caseInsensitive]
        )
        // metal|cuda|rocm SSD streaming total expert budget X GiB = A headroom [+ B full layers] + C dynamic (N experts, M MiB)
        ssdBudgetRegex = try! NSRegularExpression(
            pattern: #"SSD streaming total expert budget ([\d.]+) GiB = ([\d.]+) GiB prefill headroom(?: \+ [\d.]+ GiB full layers)? \+ ([\d.]+) GiB dynamic cache \((\d+) experts, ([\d.]+) MiB each\)"#,
            options: [.caseInsensitive]
        )
        ssdLiveRegex = try! NSRegularExpression(
            pattern: #"streaming expert cache budget=(\d+) experts entries=\d+ expert=([\d.]+) MiB target=([\d.]+) GiB live=([\d.]+) GiB, hits=\d+ misses=\d+ hit_rate=([\d.]+)"#,
            options: [.caseInsensitive]
        )
        kvBudgetRegex = try! NSRegularExpression(
            pattern: #"KV disk cache (.+?) \(budget=(\d+) MiB"#,
            options: []
        )
        kvHitRegex = try! NSRegularExpression(
            pattern: #"kv cache hit text.*? tokens=(\d+).*? load=([\d.]+) ms"#,
            options: [.caseInsensitive]
        )
        contextWindowRegex = try! NSRegularExpression(
            pattern: #"context buffers .+ \(ctx=(\d+),"#,
            options: [.caseInsensitive]
        )
        contextSpanRegex = try! NSRegularExpression(
            pattern: #"ctx=(\d+)\.\.(\d+):(\d+)"#,
            options: []
        )
        generationTokensRegex = try! NSRegularExpression(
            pattern: #"\bgen=(\d+)\b"#,
            options: []
        )
    }

    func extractTokenSpeeds(from line: String) -> [TokenSpeedSample] {
        var samples: [TokenSpeedSample] = []
        let nsLine = line as NSString
        let full = NSRange(location: 0, length: nsLine.length)

        if let v = firstCapture(prefillChunkRegex, in: line, range: full) {
            samples.append(TokenSpeedSample(kind: .prefill, value: v))
        }

        if let v = firstCapture(decodeChunkRegex, in: line, range: full) {
            samples.append(TokenSpeedSample(kind: .generation, value: v))
        }

        return samples
    }

    func extractPrefillProgress(from line: String) -> PrefillProgress? {
        let nsLine = line as NSString
        let full = NSRange(location: 0, length: nsLine.length)
        guard let match = prefillPercentRegex.firstMatch(in: line, options: [], range: full),
              match.numberOfRanges >= 4,
              let currentRange = Range(match.range(at: 1), in: line),
              let totalRange = Range(match.range(at: 2), in: line),
              let pctRange = Range(match.range(at: 3), in: line),
              let current = Int(line[currentRange]),
              let total = Int(line[totalRange]),
              let percent = Double(line[pctRange])
        else { return nil }
        return PrefillProgress(current: current, total: total, percent: percent)
    }

    func extractSSDStreamingCacheUpdate(from line: String) -> SSDStreamingCacheUpdate? {
        let nsLine = line as NSString
        let full = NSRange(location: 0, length: nsLine.length)

        if let match = ssdBudgetRegex.firstMatch(in: line, options: [], range: full),
           match.numberOfRanges >= 6,
           let total = double(in: line, match: match, group: 1),
           let headroom = double(in: line, match: match, group: 2),
           let dynamic = double(in: line, match: match, group: 3),
           let experts = int(in: line, match: match, group: 4),
           let expertMiB = double(in: line, match: match, group: 5)
        {
            return .budget(
                totalGiB: total,
                headroomGiB: headroom,
                dynamicGiB: dynamic,
                experts: experts,
                expertMiB: expertMiB
            )
        }

        if let match = ssdLiveRegex.firstMatch(in: line, options: [], range: full),
           match.numberOfRanges >= 6,
           let experts = int(in: line, match: match, group: 1),
           let expertMiB = double(in: line, match: match, group: 2),
           let target = double(in: line, match: match, group: 3),
           let live = double(in: line, match: match, group: 4),
           let hitRate = double(in: line, match: match, group: 5)
        {
            return .live(
                experts: experts,
                expertMiB: expertMiB,
                targetGiB: target,
                liveGiB: live,
                hitRate: hitRate
            )
        }

        return nil
    }

    func extractKVDiskCacheUpdate(from line: String) -> KVDiskCacheUpdate? {
        let nsLine = line as NSString
        let full = NSRange(location: 0, length: nsLine.length)

        if let match = kvBudgetRegex.firstMatch(in: line, options: [], range: full),
           match.numberOfRanges >= 3,
           let pathRange = Range(match.range(at: 1), in: line),
           let budgetRange = Range(match.range(at: 2), in: line),
           let budget = UInt64(line[budgetRange])
        {
            return .budget(path: String(line[pathRange]), budgetMiB: budget)
        }

        if let match = kvHitRegex.firstMatch(in: line, options: [], range: full),
           match.numberOfRanges >= 3,
           let tokens = int(in: line, match: match, group: 1),
           let loadMs = double(in: line, match: match, group: 2)
        {
            return .hit(tokens: tokens, loadMs: loadMs)
        }

        return nil
    }

    /// All context-fill updates present on a single log line (window, span, and/or gen).
    func extractContextFillUpdates(from line: String) -> [ContextFillUpdate] {
        var updates: [ContextFillUpdate] = []
        let nsLine = line as NSString
        let full = NSRange(location: 0, length: nsLine.length)

        if let match = contextWindowRegex.firstMatch(in: line, options: [], range: full),
           let nCtx = int(in: line, match: match, group: 1)
        {
            updates.append(.window(nCtx: nCtx))
        }

        if let match = contextSpanRegex.firstMatch(in: line, options: [], range: full),
           let cached = int(in: line, match: match, group: 1),
           let prompt = int(in: line, match: match, group: 2),
           let suffix = int(in: line, match: match, group: 3)
        {
            updates.append(.span(cached: cached, prompt: prompt, suffix: suffix))
        }

        if let match = generationTokensRegex.firstMatch(in: line, options: [], range: full),
           let gen = int(in: line, match: match, group: 1)
        {
            updates.append(.generation(gen))
        }

        return updates
    }

    private func firstCapture(
        _ regex: NSRegularExpression,
        in line: String,
        range: NSRange
    ) -> Double? {
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: line)
        else { return nil }
        return Double(String(line[capture]))
    }

    private func double(in line: String, match: NSTextCheckingResult, group: Int) -> Double? {
        guard let range = Range(match.range(at: group), in: line) else { return nil }
        return Double(line[range])
    }

    private func int(in line: String, match: NSTextCheckingResult, group: Int) -> Int? {
        guard let range = Range(match.range(at: group), in: line) else { return nil }
        return Int(line[range])
    }
}

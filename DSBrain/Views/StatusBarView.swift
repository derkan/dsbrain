import SwiftUI
import AppKit

struct StatusBarView: View {
    @ObservedObject var serverManager: ServerManager
    @ObservedObject var fanController: FanController
    @ObservedObject var model: StatusBarModel

    private let ink = Color.white.opacity(0.95)
    private let inkMuted = Color.white.opacity(0.55)

    private var isRunning: Bool { serverManager.isRunning }

    var body: some View {
        HStack(spacing: 5) {
            if model.tray.showGPU {
                MetricBar(
                    label: "GPU",
                    fraction: isRunning ? (serverManager.gpuUtilization ?? 0) : 0,
                    muted: !isRunning,
                    ink: ink,
                    inkMuted: inkMuted
                )
            }
            if model.tray.showGPUMem {
                MetricBar(
                    label: "MEM",
                    fraction: isRunning ? (serverManager.gpuMemoryFraction ?? 0) : 0,
                    muted: !isRunning,
                    ink: ink,
                    inkMuted: inkMuted,
                    fillColor: isRunning
                        ? memoryPressureFill(serverManager.systemMemoryPressure)
                        : nil,
                    helpExtra: isRunning
                        ? serverManager.systemMemoryPressure.map { " · pressure: \($0.label)" }
                        : nil
                )
            }
            if model.tray.showPrefillTPS || model.tray.showGenTPS {
                VStack(alignment: .leading, spacing: 0) {
                    if model.tray.showPrefillTPS {
                        RateLine(
                            prefix: "P",
                            value: isRunning ? serverManager.prefillTokensPerSecond : nil,
                            muted: !isRunning,
                            ink: ink,
                            inkMuted: inkMuted
                        )
                    }
                    if model.tray.showGenTPS {
                        if let pct = serverManager.prefillPercent, isRunning {
                            PrefillPercentLine(percent: pct, ink: ink)
                        } else {
                            RateLine(
                                prefix: "T",
                                value: isRunning ? serverManager.genTokensPerSecond : nil,
                                muted: !isRunning,
                                ink: ink,
                                inkMuted: inkMuted
                            )
                        }
                    }
                }
            }
            if model.tray.showCtx || model.tray.showSSDHit {
                VStack(alignment: .leading, spacing: 0) {
                    if model.tray.showCtx {
                        CtxFillLine(
                            fill: isRunning ? serverManager.contextFill : nil,
                            ink: ink,
                            inkMuted: inkMuted
                        )
                    }
                    if model.tray.showSSDHit {
                        SSDHitLine(
                            hitRate: isRunning ? serverManager.ssdStreamingCache?.hitRate : nil,
                            ink: ink,
                            inkMuted: inkMuted
                        )
                    }
                }
            }
            // Gap after P/T/C/S before fan/temp column.
            if (model.tray.showPrefillTPS || model.tray.showGenTPS
                || model.tray.showCtx || model.tray.showSSDHit)
                && (model.tray.showFanRPM || model.tray.showGPUTemp)
            {
                Color.clear.frame(width: 4)
            }
            if model.tray.showFanRPM || model.tray.showGPUTemp {
                fanMetricsColumn
            }
            // Gap after F/G before the brain glyph.
            if model.tray.showFanRPM || model.tray.showGPUTemp {
                Color.clear.frame(width: 4)
            }

            brainGlyph
        }
        .fixedSize()
    }

    @ViewBuilder
    private var fanMetricsColumn: some View {
        let showFan = model.tray.showFanRPM
            && fanController.snapshot.hasFans
            && fanController.snapshot.primaryRPM != nil
        let gpuTemp = model.tray.showGPUTemp ? validGPUTemp(fanController.snapshot.gpuTempC) : nil

        if showFan || gpuTemp != nil {
            VStack(alignment: .leading, spacing: 0) {
                if showFan, let rpm = fanController.snapshot.primaryRPM {
                    FanRateLine(rpm: rpm, ink: ink)
                }
                if let gpuTemp {
                    GPUTempLine(celsius: gpuTemp, ink: ink)
                }
            }
        }
    }

    private func validGPUTemp(_ value: Double?) -> Int? {
        guard let value, value > 0, value < 150 else { return nil }
        return Int(value.rounded())
    }

    /// Activity Monitor memory-pressure palette (green / yellow / red).
    private func memoryPressureFill(_ pressure: SystemMemorySampler.Pressure?) -> Color {
        switch pressure {
        case .warning:
            return Color(nsColor: .systemYellow)
        case .critical:
            return Color(nsColor: .systemRed)
        case .normal, .none:
            return Color(nsColor: .systemGreen)
        }
    }

    private var brainGlyph: some View {
        Image(systemName: "brain")
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(ink)
            .frame(width: 16, height: 16)
            .overlay(alignment: .bottom) {
                Circle()
                    .fill(Color(nsColor: model.trayStatus.color))
                    .frame(width: 6, height: 6)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.35), lineWidth: 0.5)
                    )
                    .opacity(model.badgePulseDimmed ? 0.45 : 1)
                    .offset(y: 1)
            }
            .accessibilityLabel("DSBrain")
    }
}

/// Prefill % in the T-rate slot: "%:" + horizontal bar (same thickness as GPU/MEM).
private struct PrefillPercentLine: View {
    let percent: Double
    let ink: Color

    /// Match vertical MetricBar track width (thickness when laid horizontal).
    private let barThickness: CGFloat = 7
    /// Roughly the width of "T: 214tk/s" so the column does not jump.
    private let barWidth: CGFloat = 44

    var body: some View {
        let fraction = max(0, min(1, percent / 100))
        HStack(spacing: 2) {
            Text("%:")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(ink)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.accentColor.opacity(0.28))
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: max(barWidth * fraction, fraction > 0 ? 2 : 0))
            }
            .frame(width: barWidth, height: barThickness)
        }
        .frame(height: 11, alignment: .center)
        .help(String(format: "Prefill %.0f%%", percent))
        .accessibilityLabel(String(format: "Prefill %.0f percent", percent))
        .animation(.easeOut(duration: 0.15), value: percent)
    }
}

/// Compact context fill from logs (e.g. `C: 27k/131k`).
private struct CtxFillLine: View {
    let fill: ContextFillInfo?
    let ink: Color
    let inkMuted: Color

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(muted ? inkMuted : ink)
            .lineLimit(1)
            .help(help)
    }

    private var muted: Bool {
        guard let fill else { return true }
        return fill.nCtx == nil && fill.promptTokens == nil
    }

    private var label: String {
        guard let fill, fill.nCtx != nil || fill.promptTokens != nil else { return "C: —" }
        return "C: \(fill.ctxLabel)"
    }

    private var help: String {
        guard let fill, fill.nCtx != nil || fill.promptTokens != nil else {
            return "Context: waiting for ds4-server logs"
        }
        return String(
            format: "Context: %d / %@ (%.0f%%)",
            fill.tokensUsed,
            fill.nCtx.map(String.init) ?? "?",
            fill.fillFraction * 100
        )
    }
}

/// Compact SSD expert-cache hit rate from logs (e.g. `S: 87%`).
private struct SSDHitLine: View {
    let hitRate: Double?
    let ink: Color
    let inkMuted: Color

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(hitRate == nil ? inkMuted : ink)
            .lineLimit(1)
            .help(help)
            .frame(minWidth: 48, alignment: .leading)
    }

    private var label: String {
        guard let hitRate else { return "S: —" }
        return String(format: "S: %.0f%%", hitRate * 100)
    }

    private var help: String {
        guard let hitRate else {
            return "SSD expert cache: waiting for hit_rate in ds4-server logs"
        }
        return String(format: "SSD expert-cache hit rate: %.1f%%", hitRate * 100)
    }
}

private struct MetricBar: View {
    let label: String
    let fraction: Double
    let muted: Bool
    let ink: Color
    let inkMuted: Color
    var fillColor: Color? = nil
    var helpExtra: String? = nil

    var body: some View {
        HStack(spacing: 2) {
            VStack(spacing: -1) {
                ForEach(Array(label.enumerated()), id: \.offset) { _, ch in
                    Text(String(ch))
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .foregroundStyle(muted ? inkMuted : ink)
                }
            }
            .frame(width: 8)

            GeometryReader { geo in
                let h = geo.size.height
                let fill = max(0, min(1, fraction)) * h
                let activeFill = fillColor ?? ink
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(ink.opacity(muted ? 0.2 : 0.28))
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(muted ? ink.opacity(0.45) : activeFill.opacity(fillColor == nil ? 0.95 : 0.92))
                        .frame(height: max(fill, fraction > 0 ? 2 : 0))
                }
            }
            .frame(width: 7, height: 14)
        }
        .frame(height: 16)
        .help("\(label): \(Int((fraction * 100).rounded()))%\(helpExtra ?? "")")
    }
}

private struct GPUTempLine: View {
    let celsius: Int
    let ink: Color

    var body: some View {
        Text("G:\(celsius)°")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(ink)
            .lineLimit(1)
            .help("GPU: \(celsius)°C")
    }
}

private struct FanRateLine: View {
    let rpm: Int
    let ink: Color

    var body: some View {
        Text("F:\(rpm)")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(ink)
            .lineLimit(1)
            .help("Fan: \(rpm) RPM")
    }
}

private struct RateLine: View {
    let prefix: String
    let value: Double?
    let muted: Bool
    let ink: Color
    let inkMuted: Color

    var body: some View {
        Text(formatted)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(muted || value == nil ? inkMuted : ink)
            .lineLimit(1)
    }

    private var formatted: String {
        if let value {
            if value >= 10 {
                return String(format: "%@: %.0ftk/s", prefix, value)
            }
            return String(format: "%@: %.1ftk/s", prefix, value)
        }
        return "\(prefix): —"
    }
}

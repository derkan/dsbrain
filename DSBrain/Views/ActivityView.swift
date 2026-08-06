import SwiftUI

struct ActivityView: View {
    @ObservedObject var serverManager: ServerManager
    @State private var isExpanded = true

    private var badge: String {
        if !serverManager.isRunning { return "stopped" }
        if let pct = serverManager.prefillPercent {
            return String(format: "prefill %.0f%%", pct)
        }
        if serverManager.isRequestBusy { return "busy" }
        return "ready"
    }

    var body: some View {
        AccordionSection(
            title: "Activity",
            badge: badge,
            isExpanded: $isExpanded
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if !serverManager.isRunning {
                    Text("Server stopped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    prefillProgressSection
                    ctxFillSection
                    ssdCacheSection
                    kvCacheSection
                    speedChips
                }

                if let error = serverManager.errorMessage {
                    lastErrorBlock(error)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var prefillProgressSection: some View {
        if let pct = serverManager.prefillPercent {
            VStack(alignment: .leading, spacing: 4) {
                Text("Prefill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ProgressView(value: pct / 100.0)
                    .progressViewStyle(.linear)
                Text(String(format: "%.1f%%", pct))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.blue)
            }
        }
    }

    @ViewBuilder
    private var ctxFillSection: some View {
        if let fill = serverManager.contextFill, fill.nCtx != nil || fill.promptTokens != nil {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Context")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text("\(fill.ctxLabel) · \(Int((fill.fillFraction * 100).rounded()))%")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: fill.fillFraction)
                    .progressViewStyle(.linear)
                    .tint(serverManager.isRequestBusy ? Color.accentColor : Color.secondary.opacity(0.6))
            }
            .help("Context tokens used / n_ctx (from ds4-server logs)")
        }
    }

    @ViewBuilder
    private var ssdCacheSection: some View {
        if let cache = serverManager.ssdStreamingCache {
            Text(cache.summaryLine)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .help(
                    String(
                        format: "Total budget %.2f GiB (%.2f headroom + %.2f dynamic)",
                        cache.totalBudgetGiB,
                        cache.prefillHeadroomGiB,
                        cache.dynamicCacheGiB
                    )
                )
        }
    }

    @ViewBuilder
    private var kvCacheSection: some View {
        if let cache = serverManager.kvDiskCache {
            Text(cache.summaryLine)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .help(cache.path.map { "KV disk cache at \($0)" } ?? "KV disk cache")
        }
    }

    private var speedChips: some View {
        HStack(spacing: 6) {
            speedChip(
                label: "P",
                value: serverManager.prefillTokensPerSecond,
                tint: .blue
            )
            speedChip(
                label: "T",
                value: serverManager.genTokensPerSecond,
                tint: .orange
            )
            Spacer(minLength: 0)
        }
    }

    private func speedChip(label: String, value: Double?, tint: Color) -> some View {
        let text: String = {
            guard let value else { return "—" }
            if value >= 100 {
                return String(format: "%.0f", value)
            }
            return String(format: "%.1f", value)
        }()

        return HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text("\(text) tk/s")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(value == nil ? .tertiary : .primary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private func lastErrorBlock(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Last error")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.red.opacity(0.9))
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

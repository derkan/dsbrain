import SwiftUI
import SMCKit

struct FanStatusView: View {
    @ObservedObject var fanController: FanController
    @State private var isExpanded = false

    private var snapshot: FanSnapshot { fanController.snapshot }

    private var badge: String? {
        guard snapshot.hasFans else { return nil }
        if let rpm = snapshot.primaryRPM {
            return "\(rpm) RPM"
        }
        return "\(snapshot.fans.count)"
    }

    var body: some View {
        AccordionSection(
            title: "Fans",
            badge: badge,
            isExpanded: $isExpanded,
            trailing: { headerAuthTrailing }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if !fanController.fansEnabled {
                    Text("Fan monitoring disabled in Preferences")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !snapshot.hasFans {
                    Text("No fans detected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    if fanController.showTempsInPopover {
                        tempRow
                    }

                    Text(fanController.controlIntentLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if let rulesStatus = fanController.rulesStatusMessage {
                        Text(rulesStatus)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    if let error = fanController.authorizationError,
                       fanController.fansEnabled,
                       !fanController.helperAuthorized
                    {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(snapshot.fans) { fan in
                        fanRow(fan)
                    }

                    if fanController.helperAuthorized {
                        Button("Reset to Auto") {
                            fanController.resetFansNow()
                        }
                        .controlSize(.small)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var headerAuthTrailing: some View {
        if fanController.fansEnabled && !fanController.helperAuthorized {
            if FanHelperClient.helperExists {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Button("Authorize") {
                        fanController.authorizeHelper()
                    }
                    .buttonStyle(.link)
                    .font(.caption2)
                    .controlSize(.mini)
                }
                .help("Fan control requires a setuid smc-helper")
            } else {
                Text("helper missing")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("smc-helper missing from app bundle. Rebuild with make bundle.")
            }
        }
    }

    private var tempRow: some View {
        HStack(spacing: 8) {
            tempChip("CPU", snapshot.cpuTempC)
            tempChip("GPU", snapshot.gpuTempC)
            tempChip("Bat", snapshot.batteryTempC)
            Spacer(minLength: 0)
        }
    }

    private func tempChip(_ label: String, _ value: Double?) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value.map { String(format: "%.0f°C", $0) } ?? "—")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(value == nil ? .tertiary : .primary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.1), in: Capsule())
    }

    private func fanRow(_ fan: FanInfo) -> some View {
        let mode = fanController.displayMode(for: fan)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "wind")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(fan.name)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text(mode.label)
                    .font(.caption2)
                    .foregroundStyle(mode.isAutomatic ? Color.secondary : Color.orange)
            }

            HStack(spacing: 12) {
                metric("Now", "\(fan.currentRPM)")
                metric("Min", "\(fan.minRPM)")
                metric("Max", "\(fan.maxRPM)")
                if !mode.isAutomatic {
                    metric("Tgt", "\(fan.targetRPM)")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(.caption2, design: .monospaced))
        }
    }
}

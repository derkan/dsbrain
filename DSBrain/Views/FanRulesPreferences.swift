import SwiftUI

struct FanRulesPreferences: View {
    @Binding var fansEnabled: Bool
    @Binding var pollIntervalText: String
    @Binding var showTempsInPopover: Bool
    @Binding var rulesEnabled: Bool
    @Binding var onQuitReset: Bool
    @Binding var rules: [FanRule]
    var onRemoveRule: (UUID) -> Void
    @ObservedObject var fanController: FanController

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enable fan monitoring", isOn: $fansEnabled)

                HStack {
                    Text("Poll interval (seconds)")
                    Spacer()
                    TextField("2", text: $pollIntervalText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .multilineTextAlignment(.trailing)
                        .font(.system(.body, design: .monospaced))
                }

                Toggle("Show SMC temperatures in popover", isOn: $showTempsInPopover)

                Divider()

                HStack {
                    Toggle("Auto-trigger rules engine", isOn: $rulesEnabled)
                        .disabled(!fansEnabled)
                    Spacer()
                    authorizationBadge
                }

                if !fanController.helperAuthorized {
                    HStack(spacing: 8) {
                        Text("Fan control requires a setuid smc-helper.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Authorize…") {
                            fanController.authorizeHelper()
                        }
                        .buttonStyle(.link)
                        .controlSize(.small)
                    }
                    if let error = fanController.authorizationError {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }

                Toggle("Reset fans to auto on quit", isOn: $onQuitReset)
                    .disabled(!rulesEnabled)

                if rulesEnabled {
                    rulesList
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Fans", systemImage: "wind")
        }
    }

    private var authorizationBadge: some View {
        Group {
            if fanController.helperAuthorized {
                Text("Helper authorized")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else if FanHelperClient.helperExists {
                Text("Helper not authorized")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Text("Helper missing")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var rulesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($rules) { $rule in
                FanRuleEditorRow(rule: $rule, onRemove: { onRemoveRule(rule.id) })
            }

            Button {
                rules.append(FanRule(enabled: true))
            } label: {
                Label("Add rule", systemImage: "plus.circle.fill")
            }
            .controlSize(.small)
        }
    }
}

private struct FanRuleEditorRow: View {
    @Binding var rule: FanRule
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("", isOn: $rule.enabled)
                    .labelsHidden()
                Picker("Sensor", selection: $rule.sensor) {
                    ForEach(FanSensor.allCases) { sensor in
                        Text(sensor.label).tag(sensor)
                    }
                }
                .frame(width: 120)

                Picker("Type", selection: $rule.type) {
                    ForEach(FanRuleType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
                .frame(width: 130)

                Spacer()

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }

            if rule.type == .threshold {
                HStack {
                    Text("When ≥")
                    TextField("°C", value: $rule.thresholdC, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                    Text("°C →")
                    Slider(value: $rule.targetSpeedPercent, in: 0...100, step: 1)
                    Text("\(Int(rule.targetSpeedPercent))%")
                        .font(.caption.monospaced())
                        .frame(width: 36, alignment: .trailing)
                }
                .font(.caption)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("From")
                        TextField("min", value: $rule.minTempC, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 52)
                        Text("°C to")
                        TextField("max", value: $rule.maxTempC, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 52)
                        Text("°C")
                    }
                    HStack {
                        Text("Speed at min °C")
                        Slider(value: $rule.minSpeedPercent, in: 0...100, step: 1)
                        Text("\(Int(rule.minSpeedPercent))%")
                            .frame(width: 36, alignment: .trailing)
                    }
                    HStack {
                        Text("Speed at max °C")
                        Slider(value: $rule.maxSpeedPercent, in: 0...100, step: 1)
                        Text("\(Int(rule.maxSpeedPercent))%")
                            .frame(width: 36, alignment: .trailing)
                    }
                    Text("Above max °C stays at max speed %. Linear ramp between min and max °C.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}

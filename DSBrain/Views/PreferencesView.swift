import SwiftUI
import AppKit

struct PreferencesView: View {
    @StateObject private var viewModel = PreferencesViewModel()
    @ObservedObject var fanController: FanController
    var onSaveAndRestart: ((AppConfig) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    serverSection
                    featuresSection
                    projectsTerminalSection
                    traySection
                    fansSection
                    commandPreviewSection
                }
                .padding(16)
            }

            Divider()

            HStack {
                Button("Reset Defaults") { viewModel.reset() }
                    .controlSize(.small)

                Spacer()

                Button("Cancel") {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    NSApp.keyWindow?.close()
                }
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)

                Button("Save & Restart") {
                    // Commit any in-progress text editing before reading view model.
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    let config = viewModel.save()
                    onSaveAndRestart?(config)
                    NSApp.keyWindow?.close()
                }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .onAppear { viewModel.load() }
        .frame(minWidth: 520, idealWidth: 540, minHeight: 560)
    }

    private var serverSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Launch command")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                MultilineTextEditor(text: $viewModel.launchCommand)
                    .frame(minHeight: 120, maxHeight: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                Text("One flag per line is fine (no trailing \\). Use `ds4-server` (PATH) or an absolute binary path — that sets cwd. Include --host / --port.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("Adopt endpoint: \(viewModel.parsedEndpoint)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        } label: {
            Label("Server", systemImage: "terminal")
        }
    }

    private var featuresSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Start server automatically on launch", isOn: $viewModel.autoStart)
                HStack {
                    Text("Log lines in popover")
                    Spacer()
                    TextField("20", text: $viewModel.maxLinesText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: viewModel.maxLinesText) { newValue in
                            let digits = newValue.filter(\.isNumber)
                            if digits != newValue { viewModel.maxLinesText = digits }
                        }
                }

                Divider()

                Toggle("Restart server when system RAM is high", isOn: $viewModel.memoryWatchdogEnabled)
                Text("Uses host memory (not tray GPU MEM). Restarts the owned ds4-server process.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Toggle("Also kill adopted (external) servers", isOn: $viewModel.memoryWatchdogKillAdopted)
                    .disabled(!viewModel.memoryWatchdogEnabled)
                Text("Off (default): leave manually launched ds4-server alone. On: SIGTERM/SIGKILL then relaunch.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                HStack {
                    Text("Max system RAM %")
                    Spacer()
                    TextField("90", text: $viewModel.memoryWatchdogMaxPercentText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .disabled(!viewModel.memoryWatchdogEnabled)
                        .onChange(of: viewModel.memoryWatchdogMaxPercentText) { newValue in
                            let digits = newValue.filter(\.isNumber)
                            if digits != newValue { viewModel.memoryWatchdogMaxPercentText = digits }
                        }
                }
                HStack {
                    Text("Cooldown (seconds)")
                    Spacer()
                    TextField("180", text: $viewModel.memoryWatchdogCooldownText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .disabled(!viewModel.memoryWatchdogEnabled)
                        .onChange(of: viewModel.memoryWatchdogCooldownText) { newValue in
                            let digits = newValue.filter(\.isNumber)
                            if digits != newValue { viewModel.memoryWatchdogCooldownText = digits }
                        }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Features", systemImage: "switch.2")
        }
    }

    private var projectsTerminalSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Used when Projects opens Pi, OMP, or Codex. Cursor always uses the Cursor app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Terminal app")
                    Spacer()
                    Picker("", selection: $viewModel.terminalAppPath) {
                        ForEach(viewModel.terminalAppOptions) { option in
                            Text(option.name).tag(option.path)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                    Button("Other…") {
                        viewModel.chooseCustomTerminalApp()
                    }
                    .controlSize(.small)
                }
                Text(viewModel.terminalAppPath)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text("iTerm and Terminal use a dedicated launch path. Any other .app is opened with the launch script (best-effort).")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Projects / Terminal", systemImage: "folder")
        }
    }

    private var traySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Compact metrics beside the menu-bar icon. P/T speeds use a live ~3s window from ds4-server logs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show GPU utilization", isOn: $viewModel.showGPU)
                Toggle("Show GPU memory (MEM)", isOn: $viewModel.showGPUMem)
                Toggle("Show prefill speed (P:)", isOn: $viewModel.showPrefillTPS)
                Toggle("Show generation speed (T:)", isOn: $viewModel.showGenTPS)
                Toggle("Show context fill (C:)", isOn: $viewModel.showCtx)
                Toggle("Show SSD expert-cache hit (S:)", isOn: $viewModel.showSSDHit)
                Toggle("Show fan RPM (F:)", isOn: $viewModel.showFanRPM)
                Toggle("Show GPU temperature (G:°)", isOn: $viewModel.showGPUTemp)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Tray Metrics", systemImage: "menubar.rectangle")
        }
    }

    private var fansSection: some View {
        FanRulesPreferences(
            fansEnabled: $viewModel.fansEnabled,
            pollIntervalText: $viewModel.fansPollIntervalText,
            showTempsInPopover: $viewModel.fansShowTempsInPopover,
            rulesEnabled: $viewModel.fansRulesEnabled,
            onQuitReset: $viewModel.fansOnQuitReset,
            rules: $viewModel.fanRules,
            onRemoveRule: { viewModel.removeFanRule(id: $0) },
            fanController: fanController
        )
    }

    private var commandPreviewSection: some View {
        GroupBox {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(viewModel.commandPreview)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
        } label: {
            HStack(spacing: 8) {
                Label("Command Preview", systemImage: "eye")
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.commandPreviewCopyString, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Copy command to clipboard")
            }
        }
    }
}

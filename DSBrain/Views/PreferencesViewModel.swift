import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

final class PreferencesViewModel: ObservableObject {
    @Published var launchCommand: String = LaunchCommand.defaultCommand
    @Published var maxLinesText: String = "20"
    @Published var showGPU: Bool = true
    @Published var showGPUMem: Bool = true
    @Published var showPrefillTPS: Bool = true
    @Published var showGenTPS: Bool = true
    @Published var showCtx: Bool = true
    @Published var showSSDHit: Bool = true
    @Published var showFanRPM: Bool = true
    @Published var showGPUTemp: Bool = true
    @Published var autoStart: Bool = true
    @Published var memoryWatchdogEnabled: Bool = false
    @Published var memoryWatchdogMaxPercentText: String = "90"
    @Published var memoryWatchdogCooldownText: String = "180"
    @Published var memoryWatchdogKillAdopted: Bool = false
    @Published var fansEnabled: Bool = true
    @Published var fansPollIntervalText: String = "2"
    @Published var fansShowTempsInPopover: Bool = true
    @Published var fansRulesEnabled: Bool = false
    @Published var fansOnQuitReset: Bool = true
    @Published var fanRules: [FanRule] = FanRule.defaultSeed
    /// Absolute `.app` path for Pi/Codex terminal launches.
    @Published var terminalAppPath: String = TerminalApp.defaultPath()

    var terminalAppOptions: [TerminalApp.Option] {
        TerminalApp.pickerOptions(including: terminalAppPath)
    }

    var commandPreview: String {
        LaunchCommand.preview(command: launchCommand)
    }

    var commandPreviewCopyString: String { commandPreview }

    /// Host:port parsed from `--host` / `--port` in the launch command.
    var parsedEndpoint: String {
        "\(LaunchCommand.host(from: launchCommand)):\(LaunchCommand.port(from: launchCommand))"
    }

    func load() {
        apply(ConfigManager.shared.load())
    }

    func reset() {
        apply(.default)
    }

    private func apply(_ config: AppConfig) {
        launchCommand = config.server.launchCommand
        maxLinesText = String(config.maxLogLines)
        showGPU = config.tray.showGPU
        showGPUMem = config.tray.showGPUMem
        showPrefillTPS = config.tray.showPrefillTPS
        showGenTPS = config.tray.showGenTPS
        showCtx = config.tray.showCtx
        showSSDHit = config.tray.showSSDHit
        showFanRPM = config.tray.showFanRPM
        showGPUTemp = config.tray.showGPUTemp
        autoStart = config.autoStart
        memoryWatchdogEnabled = config.memoryWatchdog.enabled
        memoryWatchdogMaxPercentText = String(Int(config.memoryWatchdog.maxSystemMemoryPercent))
        memoryWatchdogCooldownText = String(Int(config.memoryWatchdog.cooldownSec))
        memoryWatchdogKillAdopted = config.memoryWatchdog.killAdopted

        fansEnabled = config.fans.enabled
        fansPollIntervalText = String(config.fans.pollIntervalSec)
        fansShowTempsInPopover = config.fans.showTempsInPopover
        fansRulesEnabled = config.fans.rules.enabled
        fansOnQuitReset = config.fans.rules.onQuitReset
        fanRules = config.fans.rules.items
        terminalAppPath = TerminalApp.resolvedPath(fromConfigured: config.terminalAppPath)
    }

    func removeFanRule(id: UUID) {
        fanRules.removeAll { $0.id == id }
    }

    func chooseCustomTerminalApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose a terminal app"
        panel.prompt = "Select"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        terminalAppPath = url.path
    }

    @discardableResult
    func save() -> AppConfig {
        var config = ConfigManager.shared.load()
        config.server = ServerConfig(
            launchCommand: launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        config.maxLogLines = Int(maxLinesText) ?? 20
        config.tray = TrayConfig(
            showGPU: showGPU,
            showGPUMem: showGPUMem,
            showPrefillTPS: showPrefillTPS,
            showGenTPS: showGenTPS,
            showCtx: showCtx,
            showSSDHit: showSSDHit,
            showFanRPM: showFanRPM,
            showGPUTemp: showGPUTemp
        )
        config.fans = FanConfig(
            enabled: fansEnabled,
            pollIntervalSec: Double(fansPollIntervalText) ?? 2,
            showTempsInPopover: fansShowTempsInPopover,
            rules: FanRulesConfig(
                enabled: fansEnabled && fansRulesEnabled,
                onQuitReset: fansOnQuitReset,
                items: fanRules
            )
        )
        config.autoStart = autoStart
        config.terminalAppPath = terminalAppPath
        let maxPct = Double(memoryWatchdogMaxPercentText) ?? 90
        let cooldown = Double(memoryWatchdogCooldownText) ?? 180
        config.memoryWatchdog = MemoryWatchdogConfig(
            enabled: memoryWatchdogEnabled,
            maxSystemMemoryPercent: min(max(maxPct, 1), 99),
            cooldownSec: max(cooldown, 30),
            killAdopted: memoryWatchdogKillAdopted
        )
        ConfigManager.shared.save(config)
        return config
    }
}

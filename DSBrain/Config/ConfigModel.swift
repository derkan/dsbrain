import Foundation

struct ServerConfig: Codable {
    /// Full launch command with absolute paths (includes `--host` / `--port`).
    var launchCommand: String

    enum CodingKeys: String, CodingKey {
        case launchCommand = "launch_command"
    }

    init(launchCommand: String = LaunchCommand.defaultCommand) {
        self.launchCommand = launchCommand
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        launchCommand =
            try c.decodeIfPresent(String.self, forKey: .launchCommand) ?? LaunchCommand.defaultCommand
    }

    static var `default`: Self { ServerConfig() }

    /// Parsed from `--host` in `launchCommand`.
    var host: String { LaunchCommand.host(from: launchCommand) }

    /// Parsed from `--port` in `launchCommand`.
    var port: Int { LaunchCommand.port(from: launchCommand) }
}

/// Which compact metrics appear beside the tray brain icon.
struct TrayConfig: Codable, Equatable {
    var showGPU: Bool
    var showGPUMem: Bool
    var showPrefillTPS: Bool
    var showGenTPS: Bool
    var showCtx: Bool
    var showSSDHit: Bool
    var showFanRPM: Bool
    var showGPUTemp: Bool

    enum CodingKeys: String, CodingKey {
        case showGPU = "show_gpu"
        case showGPUMem = "show_gpu_mem"
        case showPrefillTPS = "show_prefill_tps"
        case showGenTPS = "show_gen_tps"
        case showCtx = "show_ctx"
        case showSSDHit = "show_ssd_hit"
        case showFanRPM = "show_fan_rpm"
        case showGPUTemp = "show_gpu_temp"
    }

    init(
        showGPU: Bool = true,
        showGPUMem: Bool = true,
        showPrefillTPS: Bool = true,
        showGenTPS: Bool = true,
        showCtx: Bool = true,
        showSSDHit: Bool = true,
        showFanRPM: Bool = true,
        showGPUTemp: Bool = true
    ) {
        self.showGPU = showGPU
        self.showGPUMem = showGPUMem
        self.showPrefillTPS = showPrefillTPS
        self.showGenTPS = showGenTPS
        self.showCtx = showCtx
        self.showSSDHit = showSSDHit
        self.showFanRPM = showFanRPM
        self.showGPUTemp = showGPUTemp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TrayConfig.default
        showGPU = try c.decodeIfPresent(Bool.self, forKey: .showGPU) ?? d.showGPU
        showGPUMem = try c.decodeIfPresent(Bool.self, forKey: .showGPUMem) ?? d.showGPUMem
        showPrefillTPS = try c.decodeIfPresent(Bool.self, forKey: .showPrefillTPS) ?? d.showPrefillTPS
        showGenTPS = try c.decodeIfPresent(Bool.self, forKey: .showGenTPS) ?? d.showGenTPS
        showCtx = try c.decodeIfPresent(Bool.self, forKey: .showCtx) ?? d.showCtx
        showSSDHit = try c.decodeIfPresent(Bool.self, forKey: .showSSDHit) ?? d.showSSDHit
        showFanRPM = try c.decodeIfPresent(Bool.self, forKey: .showFanRPM) ?? d.showFanRPM
        showGPUTemp = try c.decodeIfPresent(Bool.self, forKey: .showGPUTemp) ?? d.showGPUTemp
    }

    static var `default`: Self { TrayConfig() }

    var showsAnyMetric: Bool {
        showGPU || showGPUMem || showPrefillTPS || showGenTPS || showCtx || showSSDHit
            || showFanRPM || showGPUTemp
    }
}

/// Restart ds4-server when host (system) RAM exceeds a percent of physical DRAM.
struct MemoryWatchdogConfig: Codable, Equatable {
    var enabled: Bool
    /// 0...100; trigger when used system RAM >= this percent.
    var maxSystemMemoryPercent: Double
    /// Minimum seconds between watchdog-triggered restarts.
    var cooldownSec: Double
    /// When true, SIGTERM/SIGKILL an adopted (external) ds4-server so RAM can
    /// be freed before relaunch. Default false: detach only (matches Quit/Stop).
    var killAdopted: Bool

    enum CodingKeys: String, CodingKey {
        case enabled
        case maxSystemMemoryPercent = "max_system_memory_percent"
        case cooldownSec = "cooldown_sec"
        case killAdopted = "kill_adopted"
    }

    init(
        enabled: Bool = false,
        maxSystemMemoryPercent: Double = 90,
        cooldownSec: Double = 180,
        killAdopted: Bool = false
    ) {
        self.enabled = enabled
        self.maxSystemMemoryPercent = maxSystemMemoryPercent
        self.cooldownSec = cooldownSec
        self.killAdopted = killAdopted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MemoryWatchdogConfig.default
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        maxSystemMemoryPercent =
            try c.decodeIfPresent(Double.self, forKey: .maxSystemMemoryPercent) ?? d.maxSystemMemoryPercent
        cooldownSec = try c.decodeIfPresent(Double.self, forKey: .cooldownSec) ?? d.cooldownSec
        killAdopted = try c.decodeIfPresent(Bool.self, forKey: .killAdopted) ?? d.killAdopted
    }

    static var `default`: Self { MemoryWatchdogConfig() }
}

struct AppConfig: Codable {
    var server: ServerConfig
    var maxLogLines: Int
    var tray: TrayConfig
    var fans: FanConfig
    var memoryWatchdog: MemoryWatchdogConfig
    var autoStart: Bool
    /// Absolute path to preferred terminal `.app` for Pi/Codex. Empty → auto (iTerm if present).
    var terminalAppPath: String

    enum CodingKeys: String, CodingKey {
        case server
        case maxLogLines = "max_lines"
        case tray
        case fans
        case memoryWatchdog = "memory_watchdog"
        case autoStart = "auto_start"
        case terminalAppPath = "terminal_app"
    }

    init(
        server: ServerConfig = .default,
        maxLogLines: Int = 20,
        tray: TrayConfig = .default,
        fans: FanConfig = FanConfig(),
        memoryWatchdog: MemoryWatchdogConfig = .default,
        autoStart: Bool = true,
        terminalAppPath: String = ""
    ) {
        self.server = server
        self.maxLogLines = maxLogLines
        self.tray = tray
        self.fans = fans
        self.memoryWatchdog = memoryWatchdog
        self.autoStart = autoStart
        self.terminalAppPath = terminalAppPath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig.default
        server = try c.decodeIfPresent(ServerConfig.self, forKey: .server) ?? d.server
        maxLogLines = try c.decodeIfPresent(Int.self, forKey: .maxLogLines) ?? d.maxLogLines
        tray = try c.decodeIfPresent(TrayConfig.self, forKey: .tray) ?? d.tray
        fans = try c.decodeIfPresent(FanConfig.self, forKey: .fans) ?? d.fans
        memoryWatchdog =
            try c.decodeIfPresent(MemoryWatchdogConfig.self, forKey: .memoryWatchdog) ?? d.memoryWatchdog
        autoStart = try c.decodeIfPresent(Bool.self, forKey: .autoStart) ?? d.autoStart
        terminalAppPath = try c.decodeIfPresent(String.self, forKey: .terminalAppPath) ?? d.terminalAppPath
    }

    static var `default`: Self {
        AppConfig(
            server: .default,
            maxLogLines: 20,
            tray: .default,
            fans: FanConfig(),
            memoryWatchdog: .default,
            autoStart: true,
            // Empty means resolve at launch time (iTerm if installed).
            terminalAppPath: ""
        )
    }

    /// Effective terminal `.app` path (never empty if Terminal/iTerm exist).
    var resolvedTerminalAppPath: String {
        TerminalApp.resolvedPath(fromConfigured: terminalAppPath)
    }
}

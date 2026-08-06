import Darwin
import Foundation
import Combine

final class ServerManager: ObservableObject {
    static let shared = ServerManager()

    @Published private(set) var isRunning = false
    @Published private(set) var isAdopted = false
    @Published private(set) var prefillTokensPerSecond: Double?
    @Published private(set) var genTokensPerSecond: Double?
    @Published private(set) var prefillPercent: Double?
    @Published private(set) var gpuUtilization: Double?
    @Published private(set) var gpuMemoryFraction: Double?
    /// Host memory pressure (Activity Monitor bands); drives tray MEM bar color.
    @Published private(set) var systemMemoryPressure: SystemMemorySampler.Pressure?
    @Published private(set) var recentLogs: [String] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoadingModel = false
    @Published private(set) var isRequestBusy = false
    @Published private(set) var ssdStreamingCache: SSDStreamingCacheInfo?
    @Published private(set) var kvDiskCache: KVDiskCacheInfo?
    @Published private(set) var contextFill: ContextFillInfo?

    private var process: Process?
    private var adoptedPID: pid_t?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private let logParser = LogParser()
    private var activityTracker = TrayActivityTracker()
    private var adoptedLogTailer = AdoptedLogTailer()
    private var adoptedMonitorTimer: Timer?
    private var fileLogger: FileLogger?
    private var maxLogLines = 20
    private var startTime: Date?
    private var intentionalStop = false
    private var prefillWindow = RollingMetric(window: 3)
    private var genWindow = RollingMetric(window: 3)
    private var serverHost = LaunchCommand.defaultHost
    private var serverPort = LaunchCommand.defaultPort
    private var bindRecoveryInProgress = false
    private var currentConfig: AppConfig?
    private var lastMemoryRestartAt: Date?
    private var memoryWatchdogInProgress = false
    private var isStarting = false

    private init() {}

    func start(config: AppConfig) {
        guard !isRunning, !isStarting else { return }

        currentConfig = config
        maxLogLines = config.maxLogLines
        fileLogger = FileLogger(logDir: ConfigManager.shared.logDir)
        intentionalStop = false
        errorMessage = nil
        let command = config.server.launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            errorMessage = "Launch command is empty. Set it in Preferences."
            return
        }

        serverHost = LaunchCommand.host(from: command)
        serverPort = LaunchCommand.port(from: command)
        isStarting = true

        let host = serverHost
        let port = serverPort
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let occupants = ListeningPort.listeners(on: port, host: host)
            DispatchQueue.main.async {
                self?.finishStart(config: config, command: command, occupants: occupants)
            }
        }
    }

    private func finishStart(config: AppConfig, command: String, occupants: [ListeningProcess]) {
        isStarting = false
        guard !isRunning else { return }

        if let existing = occupants.first(where: \.isDS4Server) {
            adoptExistingServer(process: existing)
            return
        }

        if !occupants.isEmpty {
            let names = occupants.map(\.displayName).joined(separator: ", ")
            errorMessage =
                "Port \(serverPort) is in use by \(names). Stop that process or change --port in the launch command."
            return
        }

        guard let cwd = LaunchCommand.workingDirectory(from: command) else {
            errorMessage =
                "Launch command must start with an absolute path to ds4-server (relative paths like ./eko.sh are not supported)."
            return
        }
        launchOwnedProcess(config: config, command: command, workingDirectory: cwd)
    }

    /// Stop then start. Always SIGTERM/SIGKILL adopted servers so the port is freed
    /// (unlike Quit/Stop, which detach-only). Owned processes are always killed.
    func restart(with config: AppConfig) {
        currentConfig = config
        stop(killAdopted: true) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.start(config: config)
            }
        }
    }

    /// - Parameter killAdopted: When true, SIGTERM/SIGKILL an adopted ds4-server (frees RAM).
    ///   Default false preserves external processes on normal Stop/Quit.
    func stop(killAdopted: Bool = false, completion: (() -> Void)? = nil) {
        intentionalStop = true
        stopAdoptedMonitoring()

        if let pid = adoptedPID {
            adoptedPID = nil
            isAdopted = false
            markStopped()
            if killAdopted {
                Self.terminatePID(pid, timeout: 3.0) {
                    DispatchQueue.main.async { completion?() }
                }
            } else {
                completion?()
            }
            return
        }

        let proc = process
        process = nil
        clearPipes()
        markStopped()
        if let proc, proc.isRunning {
            proc.gracefulTerminate {
                DispatchQueue.main.async { completion?() }
            }
        } else {
            completion?()
        }
    }

    func tickActivity() {
        activityTracker.tick(
            tokensPerSecond: genTokensPerSecond ?? prefillTokensPerSecond
        )
        prefillPercent = activityTracker.prefillPercent
        if !isAdopted {
            isLoadingModel = activityTracker.isLoadingModel
            isRequestBusy = activityTracker.isRequestBusy
        }
        publishSpeedWindows()

        if isRunning {
            if let snap = GPUMetricsSampler.sample() {
                gpuUtilization = snap.utilization
                gpuMemoryFraction = snap.memoryFraction
            }
            systemMemoryPressure = SystemMemorySampler.currentPressure()
            evaluateMemoryWatchdog()
        } else {
            gpuUtilization = nil
            gpuMemoryFraction = nil
            systemMemoryPressure = nil
        }
    }

    func uptime() -> String {
        guard let start = startTime else { return "--:--:--" }
        let components = Calendar.current.dateComponents(
            [.hour, .minute, .second], from: start, to: Date())
        let h = components.hour ?? 0
        let m = components.minute ?? 0
        let s = components.second ?? 0
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    // MARK: - Private

    private func adoptExistingServer(process existing: ListeningProcess) {
        adoptedPID = existing.pid
        isAdopted = true
        self.process = nil
        clearPipes()
        startTime = Date()
        isRunning = true
        isLoadingModel = false
        isRequestBusy = false
        errorMessage = nil
        activityTracker.resetForStop()
        resetSpeedWindows()

        appendLog("Attached to existing ds4-server (pid \(existing.pid)) — live stdout unavailable")

        if let logPath = Self.discoverLogFile(from: existing.command) {
            appendLog("Tailing log file: \(logPath)")
            startAdoptedLogTail(path: logPath)
        } else if let todayLog = fileLogger?.todayLogPath(),
                  FileManager.default.fileExists(atPath: todayLog.path)
        {
            appendLog("Tailing DSBrain log file: \(todayLog.lastPathComponent)")
            startAdoptedLogTail(path: todayLog.path)
        }

        startAdoptedMonitor(pid: existing.pid)
    }

    private func startAdoptedLogTail(path: String) {
        adoptedLogTailer.start(path: path) { [weak self] line in
            DispatchQueue.main.async {
                self?.ingestLogLine(line, fromFile: true)
            }
        }
    }

    private func startAdoptedMonitor(pid: pid_t) {
        adoptedMonitorTimer?.invalidate()
        adoptedMonitorTimer = RunLoopTimer.schedule(every: 2.0) { [weak self] _ in
            guard let self else { return }
            if kill(pid, 0) != 0 {
                self.handleAdoptedProcessExit()
            }
        }
    }

    private func handleAdoptedProcessExit() {
        stopAdoptedMonitoring()
        adoptedPID = nil
        isAdopted = false
        markStopped()
        errorMessage = "Adopted ds4-server exited."
    }

    private func stopAdoptedMonitoring() {
        adoptedMonitorTimer?.invalidate()
        adoptedMonitorTimer = nil
        adoptedLogTailer.stop()
    }

    private func launchOwnedProcess(config: AppConfig, command: String, workingDirectory: String) {
        isAdopted = false
        adoptedPID = nil

        let stdout = Pipe()
        let stderr = Pipe()
        stdoutPipe = stdout
        stderrPipe = stderr

        let process = Process()
        process.executableURL = URL(fileURLWithPath: LaunchCommand.shellPath)
        process.arguments = ["-lc", LaunchCommand.normalizedForShell(command)]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        process.environment = ProcessInfo.processInfo.environment

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.handleTermination(of: proc)
            }
        }

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.handleOutput(from: handle)
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.handleOutput(from: handle)
        }

        do {
            try process.run()
            self.process = process
            startTime = Date()
            isRunning = true
            activityTracker.resetForStop()
            isLoadingModel = true
            isRequestBusy = false
            resetSpeedWindows()
        } catch {
            clearPipes()
            errorMessage = "Failed to start server: \(error.localizedDescription)"
            isRunning = false
            isLoadingModel = false
            isRequestBusy = false
        }
    }

    private func handleTermination(of proc: Process) {
        // Ignore stale handlers after a replacement process was launched.
        if let current = process, current !== proc { return }

        clearPipes()
        process = nil
        let wasIntentional = intentionalStop
        markStopped()
        if !wasIntentional, proc.terminationStatus != 0 {
            if errorMessage == nil {
                errorMessage = "Server exited unexpectedly (status \(proc.terminationStatus))."
            }
        }
        intentionalStop = false
    }

    private func evaluateMemoryWatchdog() {
        guard !memoryWatchdogInProgress else { return }
        guard let config = currentConfig, config.memoryWatchdog.enabled else { return }
        guard let snap = SystemMemorySampler.sample() else { return }

        let usedPct = snap.usedFraction * 100
        let maxPct = config.memoryWatchdog.maxSystemMemoryPercent
        guard usedPct >= maxPct else { return }

        let cooldown = max(config.memoryWatchdog.cooldownSec, 30)
        if let last = lastMemoryRestartAt, Date().timeIntervalSince(last) < cooldown {
            return
        }

        // Adopted + kill_adopted false: detach-only would leave the port held; skip.
        if isAdopted && !config.memoryWatchdog.killAdopted {
            let msg = String(
                format: "Memory watchdog: system RAM %.0f%% ≥ %.0f%% — adopted server left running (kill_adopted=false)",
                usedPct,
                maxPct
            )
            // Log only — do not stick this in Last error (it is not a failure).
            appendLog(msg)
            lastMemoryRestartAt = Date()
            return
        }

        memoryWatchdogInProgress = true
        lastMemoryRestartAt = Date()
        let msg = String(
            format: "Memory watchdog: system RAM %.0f%% ≥ %.0f%% — restarting",
            usedPct,
            maxPct
        )
        errorMessage = msg
        appendLog(msg)

        let killAdopted = isAdopted && config.memoryWatchdog.killAdopted
        stop(killAdopted: killAdopted) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let self else { return }
                self.memoryWatchdogInProgress = false
                self.start(config: config)
            }
        }
    }

    private static func terminatePID(_ pid: pid_t, timeout: TimeInterval, completion: @escaping () -> Void) {
        kill(pid, SIGTERM)
        DispatchQueue.global().async {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if kill(pid, 0) != 0 {
                    DispatchQueue.main.async { completion() }
                    return
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            if kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
            }
            DispatchQueue.main.async { completion() }
        }
    }

    private func markStopped() {
        isRunning = false
        prefillTokensPerSecond = nil
        genTokensPerSecond = nil
        prefillPercent = nil
        gpuUtilization = nil
        gpuMemoryFraction = nil
        systemMemoryPressure = nil
        startTime = nil
        isLoadingModel = false
        isRequestBusy = false
        activityTracker.resetForStop()
        ssdStreamingCache = nil
        kvDiskCache = nil
        contextFill = nil
        resetSpeedWindows()
    }

    private func resetSpeedWindows() {
        prefillWindow.reset()
        genWindow.reset()
    }

    private func publishSpeedWindows() {
        prefillTokensPerSecond = prefillWindow.stickyLatest()
        genTokensPerSecond = genWindow.stickyLatest()
    }

    private func clearPipes() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    private func appendLog(_ line: String) {
        fileLogger?.log(line)
        ingestLogLine(line, fromFile: false)
    }

    private func ingestLogLine(_ line: String, fromFile: Bool) {
        recentLogs.append(line)
        if recentLogs.count > maxLogLines {
            recentLogs.removeFirst(recentLogs.count - maxLogLines)
        }

        for sample in logParser.extractTokenSpeeds(from: line) {
            switch sample.kind {
            case .prefill:
                prefillWindow.record(sample.value)
            case .generation:
                genWindow.record(sample.value)
            }
        }
        publishSpeedWindows()

        if let update = logParser.extractSSDStreamingCacheUpdate(from: line) {
            ssdStreamingCache = update.applying(to: ssdStreamingCache)
        }
        if let update = logParser.extractKVDiskCacheUpdate(from: line) {
            kvDiskCache = update.applying(to: kvDiskCache)
        }
        for update in logParser.extractContextFillUpdates(from: line) {
            contextFill = update.applying(to: contextFill)
        }

        if !isAdopted || fromFile {
            activityTracker.ingest(line: line)
            isLoadingModel = activityTracker.isLoadingModel
            isRequestBusy = activityTracker.isRequestBusy
            prefillPercent = activityTracker.prefillPercent
        }
    }

    private func handleOutput(from handle: FileHandle) {
        let data = handle.availableData
        guard !data.isEmpty else { return }

        guard let string = String(data: data, encoding: .utf8) else { return }
        for line in string.components(separatedBy: .newlines).filter({ !$0.isEmpty }) {
            fileLogger?.log(line)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                if Self.isBindFailure(line) {
                    self.errorMessage = line.count <= 160 ? line : String(line.suffix(160))
                    self.handleBindFailureWhileRunning()
                    return
                }

                self.ingestLogLine(line, fromFile: false)

                if let message = Self.errorMessage(from: line) {
                    self.errorMessage = message
                }
            }
        }
    }

    private func handleBindFailureWhileRunning() {
        guard !bindRecoveryInProgress, !isAdopted else { return }
        bindRecoveryInProgress = true

        intentionalStop = true
        let proc = process
        process = nil
        clearPipes()
        markStopped()

        let host = serverHost
        let port = serverPort
        let finish: () -> Void = { [weak self] in
            DispatchQueue.global(qos: .userInitiated).async {
                let occupants = ListeningPort.listeners(on: port, host: host)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.bindRecoveryInProgress = false
                    if let existing = occupants.first(where: \.isDS4Server) {
                        self.errorMessage = nil
                        self.adoptExistingServer(process: existing)
                        return
                    }
                    if !occupants.isEmpty {
                        let names = occupants.map(\.displayName).joined(separator: ", ")
                        self.errorMessage = "Port \(port) is in use by \(names)."
                    }
                }
            }
        }

        if let proc, proc.isRunning {
            proc.gracefulTerminate(timeout: 2.0, completion: finish)
        } else {
            finish()
        }
    }

    private static func discoverLogFile(from commandLine: String) -> String? {
        let flags = ["--log-file", "--logfile"]
        let tokens = splitCommandLine(commandLine)
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            for flag in flags {
                if token == flag, index + 1 < tokens.count {
                    return tokens[index + 1]
                }
                if token.hasPrefix("\(flag)=") {
                    return String(token.dropFirst(flag.count + 1))
                }
            }
            index += 1
        }
        return nil
    }

    private static func splitCommandLine(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        var quote: Character?

        for char in line {
            if inQuotes {
                if char == quote {
                    inQuotes = false
                    quote = nil
                } else {
                    current.append(char)
                }
            } else if char == "\"" || char == "'" {
                inQuotes = true
                quote = char
            } else if char.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func isBindFailure(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("couldn't bind")
            || lower.contains("failed to bind")
            || lower.contains("address already in use")
            || lower.contains("exiting due to http server error")
    }

    private static func errorMessage(from line: String) -> String? {
        if isBindFailure(line) { return nil }
        let lower = line.lowercased()
        let patterns = [
            "failed to load model",
            "exiting due to model loading error",
            "exiting due to",
            "fatal error",
        ]
        guard patterns.contains(where: { lower.contains($0) }) else { return nil }
        if line.count <= 160 { return line }
        return String(line.suffix(160))
    }
}

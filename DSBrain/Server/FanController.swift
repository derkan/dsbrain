import Foundation
import Combine
import SMCKit

/// App-level fan control intent — distinct from raw SMC mode bytes.
enum FanControlIntent: Equatable {
    /// Rules engine off, or on but no rule matched; macOS manages fans.
    case systemAuto
    /// Rules engine actively forced fan speeds via smc-helper.
    case rulesForced
}

final class FanController: ObservableObject {
    static let shared = FanController()

    @Published private(set) var snapshot: FanSnapshot = .empty
    @Published private(set) var controlIntent: FanControlIntent = .systemAuto
    @Published private(set) var isPolling = false
    @Published private(set) var helperAuthorized = FanHelperClient.isAuthorized
    @Published var authorizationError: String?
    @Published private(set) var rulesStatusMessage: String?
    @Published private(set) var fansEnabled = true
    @Published private(set) var showTempsInPopover = true

    private var pollTimer: Timer?
    private var pollInterval: TimeInterval = 2
    private var trayNeedsSample = false
    private var rulesEnabled = false
    private var onQuitReset = true
    private var rules: [FanRule] = []
    private var wasRuleApplied = false
    private var lastSetSpeedPercent: Double?
    private var releasedAutoThisSession = false
    private var rulesLogger: FanRulesLogger?
    private var lastRulesLogKey: String?
    private var ticksSinceLastApply = 0

    private var shouldPoll: Bool {
        fansEnabled || trayNeedsSample || rulesEnabled
    }

    private init() {}

    /// Mode label for popover UI — reflects app intent, not raw SMC bits.
    func displayMode(for fan: FanInfo) -> (label: String, isAutomatic: Bool) {
        _ = fan
        switch controlIntent {
        case .systemAuto:
            return ("Auto", true)
        case .rulesForced:
            return ("Rules", false)
        }
    }

    var controlIntentLabel: String {
        switch controlIntent {
        case .systemAuto: return "System Auto"
        case .rulesForced: return "Rules Active"
        }
    }

    func start() {
        rulesLogger = FanRulesLogger(logDir: ConfigManager.shared.logDir)
        reloadConfig()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        isPolling = false
    }

    func reloadConfig() {
        let appConfig = ConfigManager.shared.load()
        let config = appConfig.fans
        fansEnabled = config.enabled
        showTempsInPopover = config.showTempsInPopover
        trayNeedsSample = appConfig.tray.showGPUTemp || appConfig.tray.showFanRPM
        pollInterval = max(1, config.pollIntervalSec)
        rulesEnabled = config.rules.enabled
        onQuitReset = config.rules.onQuitReset
        rules = config.rules.items
        helperAuthorized = FanHelperClient.isAuthorized
        lastSetSpeedPercent = nil
        lastRulesLogKey = nil
        ticksSinceLastApply = 0

        if rulesEnabled {
            releasedAutoThisSession = false
        } else {
            wasRuleApplied = false
            lastSetSpeedPercent = nil
            releasedAutoThisSession = false
            controlIntent = .systemAuto
        }

        restartPollingIfNeeded()
    }

    private func restartPollingIfNeeded() {
        pollTimer?.invalidate()
        pollTimer = nil

        guard shouldPoll else {
            isPolling = false
            snapshot = .empty
            return
        }

        isPolling = true
        pollTimer = RunLoopTimer.schedule(every: pollInterval) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    func refreshAuthorization() {
        helperAuthorized = FanHelperClient.isAuthorized
    }

    func authorizeHelper() {
        authorizationError = nil
        FanHelperClient.authorize { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.helperAuthorized = true
                self.authorizationError = nil
                self.tick()
            case .failure(let error):
                self.helperAuthorized = FanHelperClient.isAuthorized
                self.authorizationError = error.localizedDescription
            }
        }
    }

    func resetIfNeededOnQuit() {
        guard onQuitReset, wasRuleApplied else { return }
        _ = FanHelperClient.resetAll()
        wasRuleApplied = false
        lastSetSpeedPercent = nil
    }

    func resetFansNow() {
        guard FanHelperClient.resetAll() else { return }
        wasRuleApplied = false
        lastSetSpeedPercent = nil
        controlIntent = .systemAuto
        releasedAutoThisSession = true
        tick()
    }

    private func tick() {
        guard shouldPoll else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let sample = FanMetricsSampler.sample()
            DispatchQueue.main.async {
                self.snapshot = sample
                if self.rulesEnabled {
                    self.evaluateRules(for: sample)
                } else {
                    self.releaseControlWhenRulesOff(for: sample)
                }
                self.updateControlIntent(for: sample)
            }
        }
    }

    private func updateControlIntent(for sample: FanSnapshot) {
        if !rulesEnabled || !wasRuleApplied {
            controlIntent = .systemAuto
        } else {
            controlIntent = .rulesForced
        }
    }

    /// When rules are off, release any forced SMC mode so hardware matches system auto.
    private func releaseControlWhenRulesOff(for sample: FanSnapshot) {
        guard !rulesEnabled else { return }
        guard !releasedAutoThisSession else { return }
        guard FanHelperClient.isAuthorized else { return }

        let smcForced = sample.fans.contains { !$0.isAutomatic }
        guard wasRuleApplied || smcForced else { return }

        if FanHelperClient.resetAll() {
            releasedAutoThisSession = true
            wasRuleApplied = false
            lastSetSpeedPercent = nil
        }
    }

    private func evaluateRules(for sample: FanSnapshot) {
        guard FanHelperClient.isAuthorized else {
            rulesStatusMessage = "Authorize smc-helper to apply fan rules."
            logRulesOnce(key: "no-auth", message: "rules skipped: smc-helper not authorized")
            return
        }
        guard sample.hasFans else {
            rulesStatusMessage = "No fans detected."
            logRulesOnce(key: "no-fans", message: "rules skipped: no fans")
            return
        }

        if wasRuleApplied, let appliedPercent = lastSetSpeedPercent {
            let smcReverted = sample.fans.contains { !FanHelperClient.isApplied(expectedPercent: appliedPercent, fan: $0) }
            if smcReverted {
                wasRuleApplied = false
                lastSetSpeedPercent = nil
                logRulesOnce(
                    key: "reverted-\(Int(appliedPercent))",
                    message: "SMC reverted (auto or wrong target); re-applying \(Int(appliedPercent))%"
                )
            }
        }

        var maxTargetPercent: Double?
        var matchedRule: FanRule?

        for rule in rules where rule.enabled {
            guard let currentTemp = temperature(for: rule.sensor, snapshot: sample) else { continue }
            guard let candidate = rule.targetSpeedPercent(at: currentTemp) else { continue }
            if maxTargetPercent == nil || candidate > maxTargetPercent! {
                maxTargetPercent = candidate
                matchedRule = rule
            }
        }

        if let targetPercent = maxTargetPercent {
            let sensor = matchedRule.map { $0.sensor.label } ?? "?"
            let targetRPM = sample.fans.map { FanHelperClient.targetRPM(forPercent: targetPercent, fan: $0) }.max() ?? 0
            let needsApply = !wasRuleApplied
                || lastSetSpeedPercent != targetPercent
                || ticksSinceLastApply >= 3
                || sample.fans.contains { !FanHelperClient.isApplied(expectedPercent: targetPercent, fan: $0) }

            if needsApply {
                if FanHelperClient.setAllToPercent(targetPercent, fans: sample.fans) {
                    wasRuleApplied = true
                    lastSetSpeedPercent = targetPercent
                    ticksSinceLastApply = 0
                    rulesStatusMessage = "Rules: \(sensor) → \(Int(targetPercent))% (~\(targetRPM) RPM)"
                    logRulesOnce(
                        key: "apply-\(Int(targetPercent))-\(targetRPM)",
                        message: "applied \(Int(targetPercent))% ~\(targetRPM) RPM (\(sensor), gpu=\(sample.gpuTempC.map { Int($0) } ?? -1)°C cpu=\(sample.cpuTempC.map { Int($0) } ?? -1)°C)"
                    )
                } else {
                    wasRuleApplied = false
                    lastSetSpeedPercent = nil
                    let detail = FanHelperClient.lastSetError ?? "unknown"
                    rulesStatusMessage = "Failed to set \(Int(targetPercent))% (~\(targetRPM) RPM): \(detail)"
                    logRulesOnce(
                        key: "set-fail-\(Int(targetPercent))",
                        message: "setAllToPercent failed at \(Int(targetPercent))%: \(detail)"
                    )
                }
            } else {
                ticksSinceLastApply += 1
                rulesStatusMessage = "Rules: \(sensor) → \(Int(targetPercent))% (~\(targetRPM) RPM)"
            }
        } else if wasRuleApplied {
            _ = FanHelperClient.resetAll()
            wasRuleApplied = false
            lastSetSpeedPercent = nil
            ticksSinceLastApply = 0
            rulesStatusMessage = nil
            logRulesOnce(key: "reset", message: "no rule matched; reset to auto")
        } else {
            rulesStatusMessage = nil
        }
    }

    private func logRulesOnce(key: String, message: String) {
        guard lastRulesLogKey != key else { return }
        lastRulesLogKey = key
        rulesLogger?.log(message)
    }

    private func temperature(for sensor: FanSensor, snapshot: FanSnapshot) -> Double? {
        switch sensor {
        case .cpu: return snapshot.cpuTempC
        case .gpu: return snapshot.gpuTempC
        case .battery: return snapshot.batteryTempC
        }
    }
}

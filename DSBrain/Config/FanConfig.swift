import Foundation

// MARK: - Fan YAML config

struct FanConfig: Codable, Equatable {
    var enabled: Bool = true
    var pollIntervalSec: Double = 2
    var showTempsInPopover: Bool = true

    var rules: FanRulesConfig = FanRulesConfig()

    enum CodingKeys: String, CodingKey {
        case enabled
        case pollIntervalSec = "poll_interval_sec"
        case showTempsInPopover = "show_temps_in_popover"
        case rules
    }
}

struct FanRulesConfig: Codable, Equatable {
    var enabled: Bool = false
    var onQuitReset: Bool = true
    var items: [FanRule] = FanRule.defaultSeed

    enum CodingKeys: String, CodingKey {
        case enabled
        case onQuitReset = "on_quit_reset"
        case items
    }
}

struct FanRule: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var enabled: Bool = true
    var sensor: FanSensor = .cpu
    var type: FanRuleType = .threshold
    var thresholdC: Double = 75
    var targetSpeedPercent: Double = 80
    var minTempC: Double = 50
    var maxTempC: Double = 85
    var minSpeedPercent: Double = 20
    var maxSpeedPercent: Double = 100

    enum CodingKeys: String, CodingKey {
        case id, enabled, sensor, type
        case thresholdC = "threshold_c"
        case targetSpeedPercent = "target_speed_percent"
        case minTempC = "min_temp_c"
        case maxTempC = "max_temp_c"
        case minSpeedPercent = "min_speed_percent"
        case maxSpeedPercent = "max_speed_percent"
    }

    static let defaultSeed: [FanRule] = [
        FanRule(enabled: false, sensor: .cpu, type: .threshold, thresholdC: 75, targetSpeedPercent: 80),
        FanRule(enabled: false, sensor: .battery, type: .threshold, thresholdC: 40, targetSpeedPercent: 60),
    ]

    init(
        id: UUID = UUID(),
        enabled: Bool = true,
        sensor: FanSensor = .cpu,
        type: FanRuleType = .threshold,
        thresholdC: Double = 75,
        targetSpeedPercent: Double = 80,
        minTempC: Double = 50,
        maxTempC: Double = 85,
        minSpeedPercent: Double = 20,
        maxSpeedPercent: Double = 100
    ) {
        self.id = id
        self.enabled = enabled
        self.sensor = sensor
        self.type = type
        self.thresholdC = thresholdC
        self.targetSpeedPercent = targetSpeedPercent
        self.minTempC = minTempC
        self.maxTempC = maxTempC
        self.minSpeedPercent = minSpeedPercent
        self.maxSpeedPercent = maxSpeedPercent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        sensor = try c.decodeIfPresent(FanSensor.self, forKey: .sensor) ?? .cpu
        type = try c.decodeIfPresent(FanRuleType.self, forKey: .type) ?? .threshold
        thresholdC = try c.decodeIfPresent(Double.self, forKey: .thresholdC) ?? 75
        targetSpeedPercent = try c.decodeIfPresent(Double.self, forKey: .targetSpeedPercent) ?? 80
        minTempC = try c.decodeIfPresent(Double.self, forKey: .minTempC) ?? 50
        maxTempC = try c.decodeIfPresent(Double.self, forKey: .maxTempC) ?? 85
        minSpeedPercent = try c.decodeIfPresent(Double.self, forKey: .minSpeedPercent) ?? 20
        maxSpeedPercent = try c.decodeIfPresent(Double.self, forKey: .maxSpeedPercent) ?? 100
    }

    /// Target fan speed percent (0–100) for a sensor reading, or nil if rule does not apply.
    func targetSpeedPercent(at tempC: Double) -> Double? {
        guard enabled else { return nil }
        switch type {
        case .threshold:
            guard tempC >= thresholdC else { return nil }
            return targetSpeedPercent
        case .curve:
            guard tempC >= minTempC else { return nil }
            let lo = min(minSpeedPercent, maxSpeedPercent)
            let hi = max(minSpeedPercent, maxSpeedPercent)
            let span = maxTempC - minTempC
            guard span > 0 else { return hi }
            let ratio = min(max((tempC - minTempC) / span, 0), 1)
            return lo + ratio * (hi - lo)
        }
    }
}

enum FanSensor: String, Codable, CaseIterable, Identifiable {
    case cpu
    case gpu
    case battery

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .battery: return "Battery"
        }
    }
}

enum FanRuleType: String, Codable, CaseIterable, Identifiable {
    case threshold
    case curve

    var id: String { rawValue }

    var label: String {
        switch self {
        case .threshold: return "Threshold"
        case .curve: return "Curve"
        }
    }
}

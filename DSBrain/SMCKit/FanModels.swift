import Foundation

public struct FanInfo: Identifiable, Codable, Equatable {
    public let id: Int
    public let name: String
    public let currentRPM: Int
    public let minRPM: Int
    public let maxRPM: Int
    public let targetRPM: Int
    public let mode: Int

    public init(
        id: Int,
        name: String,
        currentRPM: Int,
        minRPM: Int,
        maxRPM: Int,
        targetRPM: Int,
        mode: Int
    ) {
        self.id = id
        self.name = name
        self.currentRPM = currentRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.targetRPM = targetRPM
        self.mode = mode
    }

    public var isAutomatic: Bool {
        mode == 0 || mode == 3
    }

    public var modeLabel: String {
        isAutomatic ? "Auto" : "Manual"
    }
}

public struct FanSnapshot: Equatable {
    public let fans: [FanInfo]
    public let cpuTempC: Double?
    public let gpuTempC: Double?
    public let batteryTempC: Double?
    public let sampledAt: Date

    public init(
        fans: [FanInfo],
        cpuTempC: Double?,
        gpuTempC: Double?,
        batteryTempC: Double?,
        sampledAt: Date
    ) {
        self.fans = fans
        self.cpuTempC = cpuTempC
        self.gpuTempC = gpuTempC
        self.batteryTempC = batteryTempC
        self.sampledAt = sampledAt
    }

    public var primaryRPM: Int? {
        fans.map(\.currentRPM).max()
    }

    public var hasFans: Bool {
        !fans.isEmpty
    }
}

/// JSON payload from smc-helper get
public struct FanHelperStatusJSON: Codable {
    public struct Fan: Codable {
        public let id: Int
        public let name: String
        public let currentSpeed: Int
        public let minSpeed: Int
        public let maxSpeed: Int
        public let targetSpeed: Int
        public let mode: Int

        public init(
            id: Int,
            name: String,
            currentSpeed: Int,
            minSpeed: Int,
            maxSpeed: Int,
            targetSpeed: Int,
            mode: Int
        ) {
            self.id = id
            self.name = name
            self.currentSpeed = currentSpeed
            self.minSpeed = minSpeed
            self.maxSpeed = maxSpeed
            self.targetSpeed = targetSpeed
            self.mode = mode
        }
    }

    public let fans: [Fan]
    public let cpuTemp: Double?
    public let gpuTemp: Double?
    public let batteryTemp: Double?

    public init(fans: [Fan], cpuTemp: Double?, gpuTemp: Double?, batteryTemp: Double?) {
        self.fans = fans
        self.cpuTemp = cpuTemp
        self.gpuTemp = gpuTemp
        self.batteryTemp = batteryTemp
    }

    public func toSnapshot() -> FanSnapshot {
        FanSnapshot(
            fans: fans.map {
                FanInfo(
                    id: $0.id,
                    name: $0.name,
                    currentRPM: $0.currentSpeed,
                    minRPM: $0.minSpeed,
                    maxRPM: $0.maxSpeed,
                    targetRPM: $0.targetSpeed,
                    mode: $0.mode
                )
            },
            cpuTempC: cpuTemp,
            gpuTempC: gpuTemp,
            batteryTempC: batteryTemp,
            sampledAt: Date()
        )
    }
}

extension FanSnapshot {
    public static let empty = FanSnapshot(
        fans: [],
        cpuTempC: nil,
        gpuTempC: nil,
        batteryTempC: nil,
        sampledAt: .distantPast
    )
}

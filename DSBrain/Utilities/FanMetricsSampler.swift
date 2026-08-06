import Foundation
import SMCKit

/// Reads fan RPM and SMC temperature sensors via in-process AppleSMC IOKit.
/// Fanless Macs return an empty snapshot without error.
enum FanMetricsSampler {
    private static let cpuKeys = [
        "TC0P", "TC0D", "TC0F", "TC1C", "TCAD", "TCBD",
        "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0C", "Tp0g", "Tp0h", "Te0S",
    ]
    private static let gpuKeys = [
        "TG0D", "TG0H", "TG0P", "Tg05", "Tg0j", "Tg0g", "Tg01", "Tg0c",
    ]
    private static let batteryKeys = [
        "TB0T", "TB1T", "TB2T", "Tw0P", "Ts0P", "Th0H",
    ]

    static func sample() -> FanSnapshot {
        let smc = SMC.shared
        guard smc.isOpen, let fanCountVal = smc.getValue("FNum") else {
            return .empty
        }

        let fanCount = max(0, Int(fanCountVal))
        var fans: [FanInfo] = []
        fans.reserveCapacity(fanCount)

        for index in 0..<fanCount {
            let name = smc.getStringValue("F\(index)ID") ?? "Fan \(index + 1)"
            let current = Int(smc.getValue("F\(index)Ac") ?? 0)
            let minSpeed = Int(smc.getValue("F\(index)Mn") ?? 0)
            let maxSpeed = Int(smc.getValue("F\(index)Mx") ?? 0)
            let target = Int(smc.getValue("F\(index)Tg") ?? 0)
            let mode = Int(smc.getValue(smc.fanModeKey(index)) ?? smc.getValue("F\(index)Md") ?? 0)

            fans.append(
                FanInfo(
                    id: index,
                    name: name,
                    currentRPM: current,
                    minRPM: minSpeed,
                    maxRPM: maxSpeed,
                    targetRPM: target,
                    mode: mode
                )
            )
        }

        return FanSnapshot(
            fans: fans,
            cpuTempC: firstValidTemp(keys: cpuKeys, smc: smc),
            gpuTempC: firstValidTemp(keys: gpuKeys, smc: smc),
            batteryTempC: firstValidTemp(keys: batteryKeys, smc: smc),
            sampledAt: Date()
        )
    }

    private static func firstValidTemp(keys: [String], smc: SMC) -> Double? {
        var best: Double?
        for key in keys {
            if let value = smc.getValue(key), value > 0, value < 150 {
                if best == nil || value > best! {
                    best = value
                }
            }
        }
        return best
    }
}

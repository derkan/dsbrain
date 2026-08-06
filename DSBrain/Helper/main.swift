//
// main.swift — smc-helper CLI
//
//

import Foundation
import SMCKit

func printHelp() {
    print(
        """
        SMC Fan Control Helper CLI
        Usage:
          smc-helper get
          smc-helper set <fanId> <mode> [rpm]   (mode: 0 = auto, 1 = manual)
          smc-helper reset
        """
    )
}

func getStatus() {
    let smc = SMC.shared
    guard let fanCountVal = smc.getValue("FNum") else {
        print("{}")
        return
    }

    let fanCount = Int(fanCountVal)
    var fansList: [FanHelperStatusJSON.Fan] = []

    for index in 0..<fanCount {
        let name = smc.getStringValue("F\(index)ID") ?? "Fan \(index + 1)"
        let current = Int(smc.getValue("F\(index)Ac") ?? 0)
        let minSpeed = Int(smc.getValue("F\(index)Mn") ?? 0)
        let maxSpeed = Int(smc.getValue("F\(index)Mx") ?? 0)
        let target = Int(smc.getValue("F\(index)Tg") ?? 0)
        let mode = Int(smc.getValue(smc.fanModeKey(index)) ?? smc.getValue("F\(index)Md") ?? 0)

        fansList.append(
            FanHelperStatusJSON.Fan(
                id: index,
                name: name,
                currentSpeed: current,
                minSpeed: minSpeed,
                maxSpeed: maxSpeed,
                targetSpeed: target,
                mode: mode
            )
        )
    }

    let cpuKeys = [
        "TC0P", "TC0D", "TC0F", "TC1C", "TCAD", "TCBD",
        "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0C", "Tp0g", "Tp0h", "Te0S",
    ]
    let gpuKeys = ["TG0D", "TG0H", "TG0P", "Tg05", "Tg0j", "Tg0g", "Tg01", "Tg0c"]
    let batteryKeys = ["TB0T", "TB1T", "TB2T", "Tw0P", "Ts0P", "Th0H"]

    func firstValidTemp(keys: [String]) -> Double? {
        for key in keys {
            if let val = smc.getValue(key), val > 0, val < 150 {
                return val
            }
        }
        return nil
    }

    let status = FanHelperStatusJSON(
        fans: fansList,
        cpuTemp: firstValidTemp(keys: cpuKeys),
        gpuTemp: firstValidTemp(keys: gpuKeys),
        batteryTemp: firstValidTemp(keys: batteryKeys)
    )

    if let jsonData = try? JSONEncoder().encode(status),
       let jsonString = String(data: jsonData, encoding: .utf8)
    {
        print(jsonString)
    } else {
        print("{}")
    }
}

func setFan(fanId: Int, mode: Int, speed: Int?) {
    let smc = SMC.shared

    if mode == 0 {
        let success = smc.setFanMode(fanId, mode: .automatic)
        if success {
            print("SUCCESS: Fan \(fanId) set to Automatic")
        } else {
            print("ERROR: Failed to set Fan \(fanId) to Automatic")
            exit(1)
        }
        return
    }

    guard mode == 1 else {
        print("ERROR: Invalid mode. Use 0 for auto, 1 for manual.")
        exit(1)
    }

    guard let targetSpeed = speed else {
        print("ERROR: Speed in RPM is required for manual mode")
        exit(1)
    }

    guard smc.setFanMode(fanId, mode: .forced) else {
        print("ERROR: Failed to set Fan \(fanId) mode to Manual")
        exit(1)
    }

    if smc.setFanSpeed(fanId, speed: targetSpeed) {
        usleep(150_000)
        let mode = Int(smc.getValue(smc.fanModeKey(fanId)) ?? smc.getValue("F\(fanId)Md") ?? -1)
        let actualTarget = Int(smc.getValue("F\(fanId)Tg") ?? 0)
        if mode != 1 {
            print("ERROR: Fan \(fanId) not in manual mode after set (mode=\(mode))")
            exit(1)
        }
        if actualTarget < targetSpeed - 100 {
            print("ERROR: Fan \(fanId) target \(actualTarget) RPM != requested \(targetSpeed) RPM")
            exit(1)
        }
        print("SUCCESS: Fan \(fanId) set to Manual (\(targetSpeed) RPM)")
    } else {
        print("ERROR: Failed to set Fan \(fanId) speed to \(targetSpeed) RPM")
        exit(1)
    }
}

let args = CommandLine.arguments
guard args.count > 1 else {
    printHelp()
    exit(0)
}

switch args[1].lowercased() {
case "get":
    getStatus()
case "set":
    guard args.count >= 4,
          let fanId = Int(args[2]),
          let mode = Int(args[3])
    else {
        print("ERROR: Missing arguments for 'set'")
        printHelp()
        exit(1)
    }
    let speed = args.count > 4 ? Int(args[4]) : nil
    setFan(fanId: fanId, mode: mode, speed: speed)
case "reset":
    if SMC.shared.resetFanControl() {
        print("SUCCESS: Reset fan controls")
    } else {
        print("ERROR: Failed to reset fan controls")
        exit(1)
    }
default:
    print("ERROR: Unknown command '\(args[1])'")
    printHelp()
    exit(1)
}

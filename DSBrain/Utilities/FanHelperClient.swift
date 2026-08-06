import Foundation
import AppKit
import SMCKit

enum FanHelperClient {
    enum AuthorizationError: LocalizedError {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let text): return text
            }
        }
    }
    private static let authorizedDefaultsKey = "isFanHelperAuthorized"

    static var helperPath: String {
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "smc-helper") {
            return bundled.path
        }
        let bundlePath = Bundle.main.bundlePath + "/Contents/MacOS/smc-helper"
        if FileManager.default.isExecutableFile(atPath: bundlePath) {
            return bundlePath
        }
        let buildPath = FileManager.default.currentDirectoryPath + "/.build/arm64-apple-macosx/debug/smc-helper"
        if FileManager.default.isExecutableFile(atPath: buildPath) {
            return buildPath
        }
        let releasePath = FileManager.default.currentDirectoryPath + "/.build/arm64-apple-macosx/release/smc-helper"
        if FileManager.default.isExecutableFile(atPath: releasePath) {
            return releasePath
        }
        return bundlePath
    }

    static var helperExists: Bool {
        FileManager.default.isExecutableFile(atPath: helperPath)
    }

    static var isAuthorized: Bool {
        guard helperExists else { return false }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: helperPath) else {
            return false
        }
        let ownerId = attributes[.ownerAccountID] as? Int ?? -1
        let permissions = attributes[.posixPermissions] as? Int ?? 0
        let isSetuid = (permissions & 0o4000) != 0
        return ownerId == 0 && isSetuid
    }

    static func markAuthorizationHint(_ authorized: Bool) {
        UserDefaults.standard.set(authorized, forKey: authorizedDefaultsKey)
    }

    static func fetchStatus() -> FanSnapshot? {
        guard helperExists else { return nil }
        guard let data = run(arguments: ["get"]) else { return nil }
        guard let decoded = try? JSONDecoder().decode(FanHelperStatusJSON.self, from: data) else {
            return nil
        }
        return decoded.toSnapshot()
    }

    static func setFan(id: Int, mode: Int, rpm: Int? = nil) -> Bool {
        guard helperExists, isAuthorized else {
            lastSetError = "helper missing or not authorized"
            return false
        }
        var args = ["set", String(id), String(mode)]
        if mode == 1, let rpm {
            args.append(String(rpm))
        }
        guard let result = runWithStatus(arguments: args) else {
            lastSetError = "failed to launch smc-helper"
            return false
        }
        guard result.exitCode == 0 else {
            lastSetError = result.output.isEmpty ? "exit \(result.exitCode)" : result.output
            return false
        }
        lastSetError = nil
        return true
    }

    static func targetRPM(forPercent percent: Double, fan: FanInfo) -> Int {
        let fraction = min(max(percent, 0), 100) / 100.0
        let range = Double(fan.maxRPM - fan.minRPM)
        let target = Int(Double(fan.minRPM) + range * fraction)
        return min(max(target, fan.minRPM), fan.maxRPM)
    }

    static func isApplied(expectedPercent: Double, fan: FanInfo) -> Bool {
        guard !fan.isAutomatic else { return false }
        let expected = targetRPM(forPercent: expectedPercent, fan: fan)
        let tolerance = max(50, expected / 10)
        return abs(fan.targetRPM - expected) <= tolerance
    }

    private(set) static var lastSetError: String?

    static func setAllToPercent(_ percent: Double, fans: [FanInfo]) -> Bool {
        guard helperExists, isAuthorized else {
            lastSetError = "helper missing or not authorized"
            return false
        }
        guard !fans.isEmpty else {
            lastSetError = "no fans"
            return false
        }
        var allOK = true
        for fan in fans {
            let rpm = targetRPM(forPercent: percent, fan: fan)
            if !setFan(id: fan.id, mode: 1, rpm: rpm) {
                allOK = false
            }
        }
        return allOK
    }

    static func resetAll() -> Bool {
        guard helperExists, isAuthorized else { return false }
        return run(arguments: ["reset"]) != nil
    }

    static func authorize(completion: @escaping (Result<Void, AuthorizationError>) -> Void) {
        guard helperExists else {
            completion(.failure(.message("smc-helper not found in app bundle. Rebuild with make bundle.")))
            return
        }

        let path = helperPath.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        do shell script "chown root:wheel '\(path)' && chmod +s '\(path)'" with administrator privileges
        """

        DispatchQueue.global(qos: .userInitiated).async {
            guard let appleScript = NSAppleScript(source: script) else {
                DispatchQueue.main.async {
                    completion(.failure(.message("Failed to compile authorization script.")))
                }
                return
            }

            var errorInfo: NSDictionary?
            appleScript.executeAndReturnError(&errorInfo)

            DispatchQueue.main.async {
                if let errorInfo,
                   let message = errorInfo[NSAppleScript.errorMessage] as? String
                {
                    if message.contains("Read-only file system") {
                        completion(.failure(.message("Move DSBrain.app to /Applications before authorizing the helper.")))
                    } else {
                        completion(.failure(.message(message)))
                    }
                    markAuthorizationHint(false)
                    return
                }

                if isAuthorized {
                    markAuthorizationHint(true)
                    completion(.success(()))
                } else {
                    completion(.failure(.message("Authorization did not apply setuid root to smc-helper.")))
                    markAuthorizationHint(false)
                }
            }
        }
    }

    @discardableResult
    private static func run(arguments: [String]) -> Data? {
        guard let result = runWithStatus(arguments: arguments), result.exitCode == 0 else {
            return nil
        }
        return result.data
    }

    private struct RunResult {
        let data: Data
        let exitCode: Int32
        let output: String
    }

    private static func runWithStatus(arguments: [String]) -> RunResult? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: helperPath)
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return RunResult(data: data, exitCode: task.terminationStatus, output: output)
    }
}

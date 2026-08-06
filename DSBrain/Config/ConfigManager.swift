import Foundation
import Yams

final class ConfigManager {
    static let shared = ConfigManager()

    private let configDir: URL
    let configPath: URL

    private init() {
        configDir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
            .appendingPathComponent("DSBrain")
        configPath = configDir.appendingPathComponent("config.yaml")
        createDirectoryIfNeeded()
    }

    func load() -> AppConfig {
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            let config = AppConfig.default
            save(config)
            return config
        }
        do {
            let yaml = try String(contentsOf: configPath, encoding: .utf8)
            return try YAMLDecoder().decode(AppConfig.self, from: yaml)
        } catch {
            print("Config load error: \(error)")
            return AppConfig.default
        }
    }

    func save(_ config: AppConfig) {
        do {
            let yaml = try YAMLEncoder().encode(config)
            try yaml.write(to: configPath, atomically: true, encoding: .utf8)
            // Ensure the write is what we will read back (catch silent encode quirks).
            let roundTrip = try YAMLDecoder().decode(AppConfig.self, from: yaml)
            if roundTrip.server.launchCommand != config.server.launchCommand {
                print("Config save warning: launch_command round-trip mismatch")
            }
        } catch {
            print("Config save error: \(error)")
        }
    }

    var applicationSupportDir: URL { configDir }

    var logDir: URL { configDir.appendingPathComponent("logs") }

    private func createDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(
            at: configDir, withIntermediateDirectories: true, attributes: nil)
    }
}

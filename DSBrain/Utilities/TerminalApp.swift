import Foundation
import AppKit

/// Favorite terminal for Pi/Codex launches. Stored as absolute `.app` path.
enum TerminalApp {
    static let terminalPath = "/System/Applications/Utilities/Terminal.app"
    static let iTermPath = "/Applications/iTerm.app"

    /// Absolute path when the app exists at a common location.
    static func installedPath(named name: String, candidates: [String]) -> String? {
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return path
        }
        return nil
    }

    /// Default: iTerm2 if installed, else Apple Terminal.
    static func defaultPath() -> String {
        if FileManager.default.fileExists(atPath: iTermPath) {
            return iTermPath
        }
        if FileManager.default.fileExists(atPath: terminalPath) {
            return terminalPath
        }
        // Older macOS layout.
        let legacy = "/Applications/Utilities/Terminal.app"
        if FileManager.default.fileExists(atPath: legacy) {
            return legacy
        }
        return terminalPath
    }

    /// Resolve configured path; empty or missing → default.
    static func resolvedPath(fromConfigured configured: String?) -> String {
        let trimmed = configured?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty, FileManager.default.fileExists(atPath: trimmed) {
            return trimmed
        }
        return defaultPath()
    }

    static func displayName(forPath path: String) -> String {
        let url = URL(fileURLWithPath: path)
        if let bundle = Bundle(url: url),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty
        {
            return name
        }
        return url.deletingPathExtension().lastPathComponent
    }

    /// Known terminals to offer when installed, plus any custom configured path.
    static func pickerOptions(including configured: String?) -> [Option] {
        var paths: [String] = []
        let known: [(String, [String])] = [
            ("iTerm", [iTermPath, "/Applications/iTerm2.app"]),
            ("Terminal", [terminalPath, "/Applications/Utilities/Terminal.app"]),
            ("Warp", ["/Applications/Warp.app"]),
            ("Alacritty", ["/Applications/Alacritty.app"]),
            ("Kitty", ["/Applications/kitty.app"]),
            ("WezTerm", ["/Applications/WezTerm.app"]),
            ("Ghostty", ["/Applications/Ghostty.app"]),
        ]
        for (_, candidates) in known {
            if let path = installedPath(named: "", candidates: candidates) {
                paths.append(path)
            }
        }
        if let configured = configured?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty,
           FileManager.default.fileExists(atPath: configured),
           !paths.contains(configured)
        {
            paths.append(configured)
        }
        // Stable order: default first when present.
        let preferred = defaultPath()
        paths.sort { a, b in
            if a == preferred { return true }
            if b == preferred { return false }
            return displayName(forPath: a).localizedCaseInsensitiveCompare(displayName(forPath: b))
                == .orderedAscending
        }
        return paths.map { Option(path: $0, name: displayName(forPath: $0)) }
    }

    struct Option: Identifiable, Hashable {
        var path: String
        var name: String
        var id: String { path }
    }

    enum Kind {
        case terminal
        case iTerm
        case other
    }

    static func kind(forPath path: String) -> Kind {
        let name = displayName(forPath: path).lowercased()
        let last = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        if name == "terminal" || last == "terminal.app" {
            return .terminal
        }
        if name.contains("iterm") || last.contains("iterm") {
            return .iTerm
        }
        return .other
    }
}

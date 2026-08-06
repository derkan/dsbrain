import Foundation

/// POSIX-ish shell quoting for command-preview display (not a full shell parser).
enum ShellQuoting {
    /// Characters that require double-quoting for a safe preview join.
    private static let specialCharacters = CharacterSet(charactersIn: " \t\n\"'\\$`|&;()<>*?[]{}~#!")

    /// Quote a single argv token for display.
    static func quote(_ token: String) -> String {
        if token.isEmpty {
            return "\"\""
        }
        let needsQuoting = token.unicodeScalars.contains { specialCharacters.contains($0) }
        guard needsQuoting else { return token }
        let escaped = token
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Join argv tokens with spaces, quoting each token as needed.
    static func join(arguments: [String]) -> String {
        arguments.map(quote).joined(separator: " ")
    }
}

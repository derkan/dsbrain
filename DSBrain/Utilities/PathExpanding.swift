import Foundation

enum PathExpanding {
    /// Expands a leading `~` to the current user's home directory.
    static func expandTilde(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        return NSHomeDirectory() + String(path.dropFirst())
    }

    /// Trims whitespace, expands `~`, and standardizes the path.
    static func normalize(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        return (expandTilde(trimmed) as NSString).standardizingPath
    }
}

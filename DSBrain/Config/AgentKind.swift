import Foundation

enum AgentKind: String, Codable, CaseIterable, Equatable, Identifiable {
    case pi
    case omp
    case codex
    case cursor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pi: return "Pi"
        case .omp: return "OMP"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        }
    }

    /// SF Symbol for list rows and Open-with menus.
    var systemImage: String {
        switch self {
        case .pi: return "terminal.fill"
        case .omp: return "sparkles"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .cursor: return "macwindow"
        }
    }

    /// Needs a running ds4-server (OpenAI-compatible endpoint).
    var requiresServer: Bool {
        switch self {
        case .pi, .omp, .codex: return true
        case .cursor: return false
        }
    }
}

struct ProjectEntry: Codable, Equatable, Identifiable {
    var path: String
    var name: String
    var lastAgent: AgentKind
    var lastOpenedAt: Date

    var id: String { path }

    enum CodingKeys: String, CodingKey {
        case path, name, lastAgent = "last_agent", lastOpenedAt = "last_opened_at"
    }

    init(path: String, name: String, lastAgent: AgentKind, lastOpenedAt: Date) {
        self.path = path
        self.name = name
        self.lastAgent = lastAgent
        self.lastOpenedAt = lastOpenedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        name = try c.decode(String.self, forKey: .name)
        lastAgent = try c.decode(AgentKind.self, forKey: .lastAgent)
        let raw = try c.decode(String.self, forKey: .lastOpenedAt)
        if let date = Self.parseDate(raw) {
            lastOpenedAt = date
        } else {
            lastOpenedAt = Date()
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(path, forKey: .path)
        try c.encode(name, forKey: .name)
        try c.encode(lastAgent, forKey: .lastAgent)
        try c.encode(Self.formatDate(lastOpenedAt), forKey: .lastOpenedAt)
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func formatDate(_ date: Date) -> String {
        isoFractional.string(from: date)
    }

    private static func parseDate(_ raw: String) -> Date? {
        isoFractional.date(from: raw) ?? isoBasic.date(from: raw)
    }
}

struct ProjectsFile: Codable, Equatable {
    var projects: [ProjectEntry]

    static var empty: Self { ProjectsFile(projects: []) }
}

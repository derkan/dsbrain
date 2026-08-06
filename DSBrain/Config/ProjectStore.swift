import Foundation
import Yams
import Combine

/// Recent projects launched via the Projects accordion (`projects.yaml`).
final class ProjectStore: ObservableObject {
    static let shared = ProjectStore()

    static let maxProjects = 20

    @Published private(set) var projects: [ProjectEntry] = []

    private let fileURL: URL
    private let encoder = YAMLEncoder()
    private let decoder = YAMLDecoder()

    private init() {
        fileURL = ConfigManager.shared.applicationSupportDir
            .appendingPathComponent("projects.yaml")
        reload()
    }

    func reload() {
        projects = load().projects.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    /// Insert or update by absolute path; keep newest first; cap at `maxProjects`.
    @discardableResult
    func recordOpen(path: String, agent: AgentKind, at date: Date = Date()) -> ProjectEntry {
        let normalized = Self.normalizePath(path)
        let name = (normalized as NSString).lastPathComponent
        var list = load().projects
        list.removeAll { Self.normalizePath($0.path) == normalized }
        let entry = ProjectEntry(
            path: normalized,
            name: name.isEmpty ? normalized : name,
            lastAgent: agent,
            lastOpenedAt: date
        )
        list.insert(entry, at: 0)
        if list.count > Self.maxProjects {
            list = Array(list.prefix(Self.maxProjects))
        }
        save(ProjectsFile(projects: list))
        projects = list
        return entry
    }

    func remove(path: String) {
        let normalized = Self.normalizePath(path)
        var list = load().projects
        list.removeAll { Self.normalizePath($0.path) == normalized }
        save(ProjectsFile(projects: list))
        projects = list
    }

    static func normalizePath(_ path: String) -> String {
        let url = URL(fileURLWithPath: PathExpanding.normalize(path))
        return url.resolvingSymlinksInPath().path
    }

    private func load() -> ProjectsFile {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }
        do {
            let yaml = try String(contentsOf: fileURL, encoding: .utf8)
            return try decoder.decode(ProjectsFile.self, from: yaml)
        } catch {
            print("Projects load error: \(error)")
            return .empty
        }
    }

    private func save(_ file: ProjectsFile) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let yaml = try encoder.encode(file)
            try yaml.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Projects save error: \(error)")
        }
    }
}

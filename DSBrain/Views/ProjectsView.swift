import SwiftUI
import AppKit

struct ProjectsView: View {
    @ObservedObject var serverManager: ServerManager
    @ObservedObject var projectStore: ProjectStore

    @State private var isExpanded = true
    @State private var errorMessage: String?

    private var host: String {
        LaunchCommand.host(from: ConfigManager.shared.load().server.launchCommand)
    }

    private var port: Int {
        LaunchCommand.port(from: ConfigManager.shared.load().server.launchCommand)
    }

    var body: some View {
        AccordionSection(
            title: "Projects",
            badge: projectStore.projects.isEmpty ? nil : "\(projectStore.projects.count)",
            isExpanded: $isExpanded,
            trailing: { addButton }
        ) {
            VStack(alignment: .leading, spacing: 6) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if projectStore.projects.isEmpty {
                    Text("No recent projects. Click + to open a folder with Pi, Codex, or Cursor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(projectStore.projects) { project in
                        projectRow(project)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var addButton: some View {
        Button {
            addProjectFlow()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open a folder with Pi, Codex, or Cursor")
    }

    private func projectRow(_ project: ProjectEntry) -> some View {
        HStack(spacing: 8) {
            Button {
                open(path: project.path, agent: project.lastAgent)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: project.lastAgent.systemImage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(project.name)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(project.path)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open with \(project.lastAgent.displayName)")

            Menu {
                ForEach(AgentKind.allCases) { agent in
                    Button {
                        open(path: project.path, agent: agent)
                    } label: {
                        Label(agent.displayName, systemImage: agent.systemImage)
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 16)
            .help("Open with…")
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Remove from Recents", role: .destructive) {
                projectStore.remove(path: project.path)
            }
        }
    }

    private func addProjectFlow() {
        errorMessage = nil
        guard let path = pickDirectory() else { return }
        guard let agent = pickAgent() else { return }
        open(path: path, agent: agent)
    }

    private func open(path: String, agent: AgentKind) {
        errorMessage = nil
        do {
            try AgentLauncher.launch(
                agent: agent,
                path: path,
                host: host,
                port: port,
                serverRunning: serverManager.isRunning
            )
            projectStore.recordOpen(path: path, agent: agent)
            if !isExpanded {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded = true
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pickDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Open"
        panel.message = "Choose a project folder"
        let result = panel.runModal()
        guard result == .OK, let url = panel.url else { return nil }
        return url.path
    }

    /// Modal agent chooser (reliable from a transient tray popover).
    private func pickAgent() -> AgentKind? {
        let alert = NSAlert()
        alert.messageText = "Open with"
        alert.informativeText = "Choose an agent for this folder. Pi and Codex use the local ds4-server."
        alert.alertStyle = .informational
        for agent in AgentKind.allCases {
            alert.addButton(withTitle: agent.displayName)
        }
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        // First button is .alertFirstButtonReturn (1000).
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard index >= 0, index < AgentKind.allCases.count else { return nil }
        return AgentKind.allCases[index]
    }
}

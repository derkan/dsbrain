import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var serverManager: ServerManager
    @ObservedObject var fanController: FanController

    let onRestart: () -> Void
    let onQuit: () -> Void
    let onOpenPreferences: () -> Void

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "DSBrain"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ProjectsView(
                serverManager: serverManager,
                projectStore: ProjectStore.shared
            )

            Divider()

            FanStatusView(fanController: fanController)

            Divider()

            ActivityView(serverManager: serverManager)

            Divider()

            LogView(lines: serverManager.recentLogs)

            Divider()

            actions
        }
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "brain")
                .font(.title3)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(appName)
                    .font(.headline)
                Text("v\(appVersion)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(serverManager.isRunning ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            Text(serverManager.isRunning ? "Running" : "Stopped")
                .font(.caption)
                .foregroundStyle(serverManager.isRunning ? .green : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (serverManager.isRunning ? Color.green : Color.secondary).opacity(0.12),
            in: Capsule()
        )
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if !serverManager.isRunning {
                Button("Start") {
                    serverManager.start(config: ConfigManager.shared.load())
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }

            Button("Restart") { onRestart() }
                .controlSize(.small)
                .disabled(!serverManager.isRunning)

            Spacer()

            Button("Preferences…") { onOpenPreferences() }
                .controlSize(.small)
                .keyboardShortcut(",", modifiers: .command)

            Button("Quit") { onQuit() }
                .controlSize(.small)
                .foregroundStyle(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

import Combine
import Foundation

/// Tray badge + config state for the menu-bar SwiftUI view.
final class StatusBarModel: ObservableObject {
    @Published var trayStatus: TrayStatus = .stopped
    @Published var badgePulseDimmed = false
    @Published var tray: TrayConfig

    init(tray: TrayConfig) {
        self.tray = tray
    }

    func reloadTrayConfig() {
        tray = ConfigManager.shared.load().tray
    }
}

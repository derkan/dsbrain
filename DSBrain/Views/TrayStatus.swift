import AppKit
import Foundation

enum TrayStatus: Equatable {
    case stopped
    case loading
    case ready
    case busy
    case error

    var color: NSColor {
        switch self {
        case .stopped: return .systemGray
        case .loading: return .systemYellow
        case .ready: return .systemGreen
        case .busy: return .systemBlue
        case .error: return .systemRed
        }
    }

    var tooltip: String {
        switch self {
        case .stopped: return "DSBrain — stopped"
        case .loading: return "DSBrain — loading model"
        case .ready: return "DSBrain — ready"
        case .busy: return "DSBrain — request running"
        case .error: return "DSBrain — error"
        }
    }

    static func resolve(
        isRunning: Bool,
        errorMessage: String?,
        isLoadingModel: Bool,
        isRequestBusy: Bool
    ) -> TrayStatus {
        if let errorMessage, !errorMessage.isEmpty { return .error }
        if !isRunning { return .stopped }
        if isLoadingModel { return .loading }
        if isRequestBusy { return .busy }
        return .ready
    }
}

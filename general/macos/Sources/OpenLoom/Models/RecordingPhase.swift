import Foundation

enum RecordingPhase: Equatable {
    case idle, choosingSource, ready, countdown(Int), starting, recording, pausing, paused, finishing, failed(String)

    var isSessionActive: Bool {
        switch self {
        case .countdown, .starting, .recording, .pausing, .paused, .finishing: true
        default: false
        }
    }

    var canChooseSource: Bool { !isSessionActive && self != .choosingSource }
    var isProcessing: Bool { self == .pausing || self == .finishing }

    var label: String {
        switch self {
        case .idle: "Choose what to record"
        case .choosingSource: "Choose a screen or window in the macOS picker"
        case .ready: "Ready to record"
        case .countdown(let value): "Starting in \(value)…"
        case .starting: "Starting recording…"
        case .recording: "Recording"
        case .pausing: "Saving the current segment…"
        case .paused: "Paused · capture is stopped"
        case .finishing: "Preparing your local video…"
        case .failed(let reason): reason
        }
    }
}

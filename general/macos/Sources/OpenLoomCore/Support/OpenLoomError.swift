import Foundation

public enum OpenLoomError: LocalizedError {
    case invalidSettings, invalidDimensions, invalidManifest, invalidSegment
    case invalidTitle, remoteURL, unsafePath, noMedia, invalidTrim, lowDiskSpace
    case exportUnavailable, recordingFailed(String), microphoneDenied, finishTimedOut
    case cameraDenied, cameraUnavailable, invalidReview, speechUnavailable, noAudio
    case processingTimedOut

    public var errorDescription: String? {
        switch self {
        case .invalidSettings: "Choose a supported frame rate and a countdown between 0 and 5 seconds."
        case .invalidDimensions: "The selected source has no usable video dimensions. Choose it again."
        case .invalidManifest: "The local recording metadata is invalid or from an unsupported version."
        case .invalidSegment: "The recording segment is missing or invalid. Completed segments have been kept."
        case .invalidTitle: "Use a title between 1 and 200 characters."
        case .remoteURL: "OpenLoom accepts local files only."
        case .unsafePath: "The file location is outside the private local library or points to a linked folder."
        case .noMedia: "No completed video frames were saved."
        case .invalidTrim: "The trim must stay inside the recording and include at least 0.1 seconds."
        case .lowDiskSpace: "Less than 500 MB of disk space is available. Free space before recording."
        case .exportUnavailable: "macOS could not create the local MP4 export. The original segments are safe."
        case .recordingFailed(let reason): "Recording stopped: \(reason). Completed segments have been kept."
        case .microphoneDenied: "Microphone access is unavailable. Enable it in System Settings, or turn the microphone off."
        case .finishTimedOut: "macOS did not finish the recording file in time. Completed segments have been kept."
        case .cameraDenied: "Camera access is unavailable. Allow OpenLoom in System Settings → Privacy & Security → Camera."
        case .cameraUnavailable: "The selected camera is unavailable or disconnected. Choose an available camera."
        case .invalidReview: "The note, caption, or visual edit has an invalid time or value."
        case .speechUnavailable: "On-device captions need macOS 26 or later and a speech language already installed on this Mac. OpenLoom will not download models or use a server."
        case .noAudio: "This recording has no audio track to transcribe. Enable a microphone or system audio for the next recording."
        case .processingTimedOut: "The local operation stopped responding and was cancelled. Source files have been kept. You can retry recovery; a file that never finished writing may be incomplete."
        }
    }
}

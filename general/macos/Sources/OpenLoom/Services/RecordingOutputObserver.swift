@preconcurrency import ScreenCaptureKit
import Foundation
import OpenLoomCore
import CoreMedia

/// Apple invokes delegates off the UI thread. Only lightweight notifications cross to MainActor.
@MainActor
final class RecordingOutputObserver: NSObject, SCRecordingOutputDelegate {
    private var startResult: Result<Void, Error>?
    private var finishResult: Result<Void, Error>?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var finishContinuation: CheckedContinuation<Void, Error>?
    var onFailure: ((String) -> Void)?
    private(set) var startedAt: Double?

    func waitForStart() async throws {
        if let result = startResult { return try result.get() }
        try await withCheckedThrowingContinuation { startContinuation = $0 }
    }

    func waitForFinish() async throws {
        if let result = finishResult { return try result.get() }
        try await withCheckedThrowingContinuation { finishContinuation = $0 }
    }

    func timeOut() { resolveFailure(OpenLoomError.finishTimedOut) }

    private func resolveStart(_ result: Result<Void, Error>) {
        guard startResult == nil else { return }
        startResult = result
        startContinuation?.resume(with: result)
        startContinuation = nil
    }

    private func resolveFinish(_ result: Result<Void, Error>) {
        guard finishResult == nil else { return }
        finishResult = result
        finishContinuation?.resume(with: result)
        finishContinuation = nil
    }

    private func resolveFailure(_ error: Error) {
        resolveStart(.failure(error))
        resolveFinish(.failure(error))
    }

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let hostTime = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        Task { @MainActor [weak self] in self?.startedAt = hostTime; self?.resolveStart(.success(())) }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            self?.resolveStart(.failure(OpenLoomError.noMedia))
            self?.resolveFinish(.success(()))
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.resolveFailure(OpenLoomError.recordingFailed(message))
            self?.onFailure?(message)
        }
    }
}

@MainActor
final class CaptureStreamObserver: NSObject, SCStreamDelegate {
    var onStop: ((String) -> Void)?

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.onStop?(message) }
    }
}

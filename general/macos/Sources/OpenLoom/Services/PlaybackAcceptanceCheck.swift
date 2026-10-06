@preconcurrency import AVFoundation
import OpenLoomCore

@MainActor
enum PlaybackAcceptanceCheck {
    /// Checks the controller actually mounted in RecordingDetailView, not a standalone player.
    static func verify(model: AppModel) async throws {
        try await AsyncDeadline.run(timeout: .seconds(10)) { @MainActor in
            while model.acceptancePlayer?.player.currentItem?.status != .readyToPlay {
                if let item = model.acceptancePlayer?.player.currentItem, item.status == .failed {
                    throw OpenLoomError.recordingFailed(item.error?.localizedDescription ?? "Playback failed")
                }
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        guard let playback = model.acceptancePlayer else { throw OpenLoomError.noMedia }
        playback.seek(to: 0)
        playback.player.play()
        defer { playback.player.pause() }
        try await AsyncDeadline.run(timeout: .seconds(10)) { @MainActor in
            while playback.time < 0.3 { try await Task.sleep(for: .milliseconds(50)) }
        }
    }
}

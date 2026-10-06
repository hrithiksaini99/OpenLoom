import AppKit
@preconcurrency import AVFoundation
import Foundation
import OpenLoomCore
import OSLog

/// Explicit opt-in hardware diagnostic, invoked only with --camera-lifecycle-check.
/// Runs the actual app recorder; never captures the screen or microphone. Reports contain metadata only.
@MainActor
enum CameraAcceptanceCheck {
    private struct Report: Codable {
        var status = "running"
        var step = "Starting authorized camera check"
        var timings: [String: Double] = [:]
        var recordingID: UUID?
        var duration: Double?
        var segments: Int?
        var audioTracks: Int?
        var decodedFrames: Int?
        var playbackVerified: Bool?
        var recordingPreviewVerified: Bool?
        var error: String?
    }

    static func run(model: AppModel) async {
        guard !model.isBusy, !model.isRunningCameraCheck else { return }
        model.isRunningCameraCheck = true
        let original = model.recorder.settings
        let originalTitle = model.recorder.title
        let reportURL = model.library.root.deletingLastPathComponent().appendingPathComponent("camera-check.json")
        let logger = Logger(subsystem: "org.openloom.local", category: "camera-check")
        var report = Report()
        func checkpoint(_ step: String) throws {
            report.step = step
            logger.info("Camera acceptance step: \(step, privacy: .public)")
            let data = try JSONEncoder().encode(report)
            try data.write(to: reportURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: reportURL.path)
        }
        defer {
            model.recorder.settings = original
            model.recorder.title = originalTitle
            model.recorder.modeDidChange()
            model.isRunningCameraCheck = false
            model.saveSettings()
        }
        do {
            try model.library.prepare()
            var settings = original
            settings.mode = .camera; settings.microphone = false; settings.systemAudio = false
            settings.captureClicks = false; settings.countdownSeconds = 0
            settings.cameraID = nil
            settings.resolution = .hd720; settings.framesPerSecond = 30; settings.codec = .h264
            model.recorder.settings = settings
            model.recorder.modeDidChange()
            try checkpoint("Testing preview start/stop")
            for index in 1...3 {
                let start = ProcessInfo.processInfo.systemUptime
                await model.recorder.camera.preview(settings: settings)
                guard model.recorder.camera.isPreviewing else { throw OpenLoomError.recordingFailed(model.recorder.camera.errorMessage ?? "Preview unavailable") }
                try await AsyncDeadline.run(timeout: .seconds(5)) { @MainActor in
                    while model.recorder.camera.previewFrame == nil { try await Task.sleep(for: .milliseconds(50)) }
                }
                // Let the real SwiftUI preview appear and be dismantled on each cycle.
                try await Task.sleep(for: .milliseconds(300))
                await model.recorder.camera.stopPreview()
                report.timings["previewCycle\(index)"] = ProcessInfo.processInfo.systemUptime - start
                try checkpoint("Completed preview cycle \(index)")
            }
            model.recorder.title = "Camera lifecycle acceptance test"
            try checkpoint("Starting camera-only take; audio off")
            await model.recorder.start()
            guard model.recorder.phase == .recording, let id = model.recorder.manifest?.id else {
                throw OpenLoomError.recordingFailed(model.recorder.phase.label)
            }
            report.recordingID = id
            await model.toggleFloatingCamera()
            guard model.floating.isCameraVisible, model.recorder.camera.isShowingRecordingPreview else { throw OpenLoomError.cameraUnavailable }
            try await AsyncDeadline.run(timeout: .seconds(5)) { @MainActor in
                while model.recorder.camera.previewFrame == nil { try await Task.sleep(for: .milliseconds(50)) }
            }
            await model.toggleFloatingCamera()
            guard !model.floating.isCameraVisible, model.recorder.camera.previewFrame == nil,
                  model.recorder.phase == .recording else { throw OpenLoomError.cameraUnavailable }
            await model.toggleFloatingCamera()
            try await AsyncDeadline.run(timeout: .seconds(5)) { @MainActor in
                while model.recorder.camera.previewFrame == nil { try await Task.sleep(for: .milliseconds(50)) }
            }
            report.recordingPreviewVerified = true
            try checkpoint("Recording first five seconds")
            try await Task.sleep(for: .seconds(5))
            var start = ProcessInfo.processInfo.systemUptime
            try checkpoint("Pausing and journaling source")
            await model.recorder.pause()
            report.timings["pause"] = ProcessInfo.processInfo.systemUptime - start
            guard model.recorder.phase == .paused, model.recorder.manifest?.segmentDurations.count == 1 else {
                throw OpenLoomError.recordingFailed(model.recorder.phase.label)
            }
            try checkpoint("Resuming camera take")
            await model.recorder.resume()
            guard model.recorder.phase == .recording else { throw OpenLoomError.recordingFailed(model.recorder.phase.label) }
            try checkpoint("Recording second five seconds")
            try await Task.sleep(for: .seconds(5))
            start = ProcessInfo.processInfo.systemUptime
            try checkpoint("Stopping and saving MP4")
            await model.recorder.stop()
            report.timings["stop"] = ProcessInfo.processInfo.systemUptime - start
            guard !model.recorder.camera.requiresRestart, !model.recorder.camera.isRecording,
                  !model.recorder.camera.isPreviewing, !model.recorder.camera.isShowingRecordingPreview,
                  model.recorder.camera.previewFrame == nil else { throw OpenLoomError.cameraUnavailable }
            let recording = try requireReady(id, library: model.library)
            let output = model.library.outputURL(for: id)
            report.duration = try await model.exporter.duration(of: output)
            report.segments = recording.segmentDurations.count
            report.audioTracks = try await AVURLAsset(url: output).loadTracks(withMediaType: .audio).count
            guard report.segments == 2, report.audioTracks == 0, (8...14).contains(report.duration ?? 0) else { throw OpenLoomError.invalidSegment }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 64, height: 64)
            for time in [0.5, recording.segmentDurations[0] + 0.5] {
                let (frame, _) = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
                guard frame.width > 0, frame.height > 0 else { throw OpenLoomError.noMedia }
            }
            report.decodedFrames = 2 // Frames are decoded locally; no pixels enter the report or tool output.
            try checkpoint("Verifying the mounted native player")
            try await PlaybackAcceptanceCheck.verify(model: model)
            report.playbackVerified = true
            report.status = "passed"
            model.floating.hideCamera()
            try checkpoint("Camera preview, pause/resume, stop, media metadata, and native playback verified")
            model.notice = "Camera lifecycle check passed. The local test video has no audio."
        } catch {
            report.status = "failed"; report.error = error.localizedDescription
            try? checkpoint("Camera acceptance check failed")
            model.recorder.cancelCountdown()
            if model.recorder.phase == .recording || model.recorder.phase == .paused { await model.recorder.stop() }
            await model.recorder.camera.stopPreview()
            model.floating.hideCamera()
            model.errorMessage = error.localizedDescription
        }
    }

    private static func requireReady(_ id: UUID, library: RecordingLibrary) throws -> RecordingManifest {
        guard let recording = try library.scan().recordings.first(where: { $0.id == id }), recording.status == .ready else {
            throw OpenLoomError.noMedia
        }
        return recording
    }
}

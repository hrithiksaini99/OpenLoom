import AppKit
@preconcurrency import AVFoundation
import OpenLoomCore
@preconcurrency import ScreenCaptureKit
import SwiftUI

/// Explicit --screen-lifecycle-check only. The source is this process's generated
/// test window; no desktop, other window, camera, microphone, or system audio.
@MainActor
enum ScreenAcceptanceCheck {
    private struct Report: Codable {
        var status = "running"
        var step = "Opening generated test window"
        var timings: [String: Double] = [:]
        var recordingID: UUID?
        var duration: Double?
        var segments: Int?
        var audioTracks: Int?
        var decodedFrames: Int?
        var playbackVerified: Bool?
        var error: String?
    }

    static func run(model: AppModel) async {
        guard !model.isBusy, !model.isRunningUICheck else { return }
        model.isRunningScreenCheck = true
        let original = model.recorder.settings, originalTitle = model.recorder.title
        let reportURL = model.library.root.deletingLastPathComponent().appendingPathComponent("screen-check.json")
        var report = Report()
        let window = NSWindow(contentRect: CGRect(x: 160, y: 180, width: 640, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "OpenLoom · generated capture test"
        window.contentView = NSHostingView(rootView: GeneratedScreenSource())
        func checkpoint(_ step: String) throws {
            report.step = step
            try JSONEncoder().encode(report).write(to: reportURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: reportURL.path)
        }
        defer {
            window.orderOut(nil); window.contentView = nil; window.close()
            model.recorder.settings = original; model.recorder.title = originalTitle
            model.recorder.modeDidChange(); model.isRunningScreenCheck = false
            model.saveSettings()
        }
        do {
            try model.library.prepare()
            try checkpoint("Opening generated test window")
            window.orderFront(nil)
            try await Task.sleep(for: .milliseconds(500))
            let ownWindowID = UInt32(window.windowNumber)
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let source = try await AsyncDeadline.run(timeout: .seconds(15)) {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                guard let source = content.windows.first(where: {
                    $0.windowID == ownWindowID && $0.owningApplication?.processID == ownPID
                }) else { throw OpenLoomError.recordingFailed("Generated test window was not available for capture") }
                return source
            }
            var settings = RecordingSettings()
            settings.mode = .screen; settings.microphone = false; settings.systemAudio = false
            settings.captureClicks = false; settings.showsCursor = false; settings.countdownSeconds = 0
            settings.resolution = .hd720; settings.framesPerSecond = 30; settings.codec = .h264
            model.recorder.settings = settings
            model.recorder.title = "Generated window lifecycle acceptance test"
            try model.recorder.selectAcceptanceSource(source, expectedWindowID: ownWindowID)
            try checkpoint("Recording first five seconds; audio and camera off")
            await model.recorder.start()
            guard model.recorder.phase == .recording, let id = model.recorder.manifest?.id else {
                throw OpenLoomError.recordingFailed(model.recorder.phase.label)
            }
            report.recordingID = id
            try await Task.sleep(for: .seconds(5))
            var start = ProcessInfo.processInfo.systemUptime
            try checkpoint("Pausing and journaling screen source")
            await model.recorder.pause()
            report.timings["pause"] = ProcessInfo.processInfo.systemUptime - start
            guard model.recorder.phase == .paused, model.recorder.manifest?.segmentDurations.count == 1 else {
                throw OpenLoomError.recordingFailed(model.recorder.phase.label)
            }
            try checkpoint("Resuming generated-window capture")
            await model.recorder.resume()
            guard model.recorder.phase == .recording else { throw OpenLoomError.recordingFailed(model.recorder.phase.label) }
            try await Task.sleep(for: .seconds(5))
            start = ProcessInfo.processInfo.systemUptime
            try checkpoint("Stopping and saving screen MP4")
            await model.recorder.stop()
            report.timings["stop"] = ProcessInfo.processInfo.systemUptime - start
            guard let recording = try model.library.scan().recordings.first(where: { $0.id == id }), recording.status == .ready else {
                throw OpenLoomError.noMedia
            }
            let output = model.library.outputURL(for: id)
            report.duration = try await model.exporter.duration(of: output)
            report.segments = recording.segmentDurations.count
            report.audioTracks = try await AVURLAsset(url: output).loadTracks(withMediaType: .audio).count
            guard report.segments == 2, report.audioTracks == 0, (8...14).contains(report.duration ?? 0) else { throw OpenLoomError.invalidSegment }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
            generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 64, height: 64)
            for time in [0.5, recording.segmentDurations[0] + 0.5] {
                let (frame, _) = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
                guard frame.width > 0, frame.height > 0 else { throw OpenLoomError.noMedia }
            }
            report.decodedFrames = 2
            try checkpoint("Verifying mounted native playback")
            try await PlaybackAcceptanceCheck.verify(model: model)
            report.playbackVerified = true; report.status = "passed"
            try checkpoint("Generated-window pause/resume, save, and playback verified")
            model.notice = "Screen lifecycle check passed using generated test graphics only. No camera or audio was captured."
        } catch {
            report.status = "failed"; report.error = error.localizedDescription
            try? checkpoint("Screen acceptance check failed")
            if model.recorder.phase == .recording || model.recorder.phase == .paused { await model.recorder.stop() }
            model.errorMessage = error.localizedDescription
        }
    }
}

private struct GeneratedScreenSource: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                LinearGradient(colors: [.indigo, .blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 20) {
                    Image(systemName: "record.circle").font(.system(size: 60))
                    Text("Generated capture test").font(.title.bold())
                    Text("This window contains no personal data.").font(.headline)
                    Text(String(format: "Frame clock %.2f", seconds.truncatingRemainder(dividingBy: 60)))
                        .font(.title3.monospacedDigit())
                }.foregroundStyle(.white)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

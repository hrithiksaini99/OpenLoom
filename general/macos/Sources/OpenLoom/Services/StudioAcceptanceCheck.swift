import AppKit
@preconcurrency import AVFoundation
import OpenLoomCore
import OSLog
import SwiftUI

/// Generated-content acceptance, explicitly invoked by --studio-check. No device capture.
/// Renders our own SwiftUI fixtures, never the desktop or another application's window.
@MainActor
enum StudioAcceptanceCheck {
    private struct Report: Codable {
        var status = "running"
        var step = "Starting studio check"
        var checks: [String] = []
        var images: [String] = []
        var error: String?
    }

    static func run(model: AppModel) async {
        guard !model.isBusy, !model.isRunningUICheck else { return }
        model.isRunningUICheck = true
        let original = model.recorder.settings, originalTitle = model.recorder.title
        let directory = model.library.root.deletingLastPathComponent().appendingPathComponent("UIDiagnostics", isDirectory: true)
        let reportURL = directory.appendingPathComponent("studio-check.json")
        var report = Report()
        let logger = Logger(subsystem: "org.openloom.local", category: "studio-check")
        func checkpoint(_ step: String) throws {
            report.step = step
            logger.info("Studio acceptance step: \(step, privacy: .public)")
            try JSONEncoder().encode(report).write(to: reportURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: reportURL.path)
        }
        defer {
            model.recorder.settings = original; model.recorder.title = originalTitle
            model.recorder.modeDidChange(); model.isRunningUICheck = false
            model.saveSettings()
        }
        do {
            try model.library.prepare()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            model.recorder.settings = RecordingSettings()
            model.recorder.settings.microphone = false; model.recorder.settings.systemAudio = false
            model.recorder.title = "Design walkthrough"
            model.recorder.modeDidChange()
            try checkpoint("Rendering generated capture layouts")
            for (name, width, height, scheme) in [
                ("capture-light", 940.0, 710.0, ColorScheme.light),
                ("capture-dark", 940.0, 710.0, ColorScheme.dark),
                ("capture-small", 740.0, 590.0, ColorScheme.light)
            ] {
                let content = CaptureSetupView(model: model)
                    .safeAreaInset(edge: .bottom, spacing: 0) { CaptureTransport(model: model) }
                try await render(content, width: width, height: height, scheme: scheme, to: directory.appendingPathComponent(name + ".png"))
                report.images.append(name + ".png")
            }
            report.checks.append("Generated setup layouts rendered at default/minimum sizes and light/dark appearances")
            for (name, mode) in [("camera-setup", CaptureMode.camera), ("bubble-setup", CaptureMode.screenAndCamera)] {
                model.recorder.settings.mode = mode; model.recorder.modeDidChange()
                let content = CaptureSetupView(model: model)
                    .safeAreaInset(edge: .bottom, spacing: 0) { CaptureTransport(model: model) }
                try await render(content, width: 740, height: 590, scheme: .light,
                                 to: directory.appendingPathComponent(name + ".png"))
                report.images.append(name + ".png")
            }
            model.recorder.settings.mode = .screen; model.recorder.modeDidChange()
            try model.floating.verifyWindowBehavior(model: model)
            report.checks.append("Floating panels configured for all Spaces/fullscreen; recorder position retained after hide/show and camera resized to three sizes programmatically")
            for (name, phase, elapsed) in [
                ("floating-idle", RecordingPhase.idle, 0.0),
                ("floating-recording", RecordingPhase.recording, 75.0),
                ("floating-paused", RecordingPhase.paused, 75.0),
                ("floating-saving", RecordingPhase.finishing, 75.0)
            ] {
                try await render(FloatingRecorderView(model: model, fixturePhase: phase, fixtureElapsed: elapsed),
                                 width: 482, height: 90, scheme: .light,
                                 to: directory.appendingPathComponent(name + ".png"))
                report.images.append(name + ".png")
            }
            try await render(FloatingCameraView(model: model), width: 240, height: 240, scheme: .light,
                             to: directory.appendingPathComponent("floating-camera-placeholder.png"))
            report.images.append("floating-camera-placeholder.png")
            try checkpoint("Closing and reopening the studio while floating controls remain")
            guard let studio = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain && !($0 is NSPanel) && !$0.isSheet }) else {
                throw OpenLoomError.recordingFailed("Studio window is not mounted")
            }
            studio.performClose(nil)
            guard !studio.isVisible, model.floating.isVisible else { throw OpenLoomError.recordingFailed("Floating controls did not remain after closing the studio") }
            model.showLibrary()
            try await AsyncDeadline.run(timeout: .seconds(5)) { @MainActor in
                while !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain && !($0 is NSPanel) && !$0.isSheet }) {
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
            report.checks.append("Main studio closed and reopened while floating controls and shared app state remained available")
            try checkpoint("Creating generated demo and mounting native playback")
            await model.createDemo()
            guard let demo = model.selected, demo.status == .ready else { throw OpenLoomError.noMedia }
            // Let AppKit mount the actual native player in the visible main window.
            try await Task.sleep(for: .seconds(2))
            guard NSApp.windows.contains(where: { $0.isVisible && !$0.isSheet }) else { throw OpenLoomError.recordingFailed("Main window is not visible") }
            try await PlaybackAcceptanceCheck.verify(model: model)
            report.checks.append("Mounted native player loaded the generated demo and advanced playback in the main window")
            let note = TimedNote(time: 1, text: "Studio acceptance note", kind: .note)
            model.saveNote(for: demo.id, noteID: note.id, time: note.time, text: note.text, kind: note.kind)
            guard model.selected?.notes.contains(where: { $0.id == note.id }) == true else { throw OpenLoomError.invalidReview }
            model.removeNote(for: demo.id, noteID: note.id)
            guard model.selected?.notes.contains(where: { $0.id == note.id }) == false else { throw OpenLoomError.invalidReview }
            report.checks.append("Timestamped note creation and removal persisted")
            model.search = "generated"
            guard model.filteredRecordings.contains(where: { $0.id == demo.id }) else { throw OpenLoomError.invalidReview }
            model.search = ""
            report.checks.append("Local library search found generated recording metadata")
            try checkpoint("Exporting trim through the app coordinator")
            let trimmed = try await model.exportTrim(demo, start: 1, end: 3)
            let length = try await model.exporter.duration(of: trimmed)
            guard abs(length - 2) < 0.15, !model.isExporting else { throw OpenLoomError.invalidTrim }
            report.checks.append("Trim exported inside the signed app sandbox and released its busy state")
            try checkpoint("Exporting timed drawing and zoom through the app coordinator")
            let edits = [
                VisualCue(start: 1, end: 3, tool: .rectangle, points: [.init(x: 0.2, y: 0.2), .init(x: 0.8, y: 0.7)], color: .yellow),
                VisualCue(start: 3, end: 5, tool: .zoom, points: [.init(x: 0.6, y: 0.4)], color: .yellow, zoom: 1.8)
            ]
            model.errorMessage = nil
            await model.exportPolished(demo, edits: edits, revealResult: false)
            guard model.errorMessage == nil, !model.isExporting else { throw OpenLoomError.recordingFailed(model.errorMessage ?? "Export did not release busy state") }
            report.checks.append("Drawing and zoom export completed inside the signed app sandbox")
            guard let updated = model.selected else { throw OpenLoomError.invalidManifest }
            let captions = try model.library.exportCaptions(updated)
            let review = try model.library.exportReview(updated)
            guard captions.count == 2, FileManager.default.fileExists(atPath: review.path) else { throw OpenLoomError.invalidReview }
            report.checks.append("Sample captions and review document exported locally")
            let playback = PlaybackController()
            try await render(ReviewPane(model: model, recording: updated, playback: playback), width: 320, height: 600, scheme: .light,
                       to: directory.appendingPathComponent("review-inspector.png"))
            report.images.append("review-inspector.png")
            try await render(ReviewPane(model: model, recording: updated, playback: playback, initialTab: 1), width: 320, height: 600, scheme: .dark,
                             to: directory.appendingPathComponent("review-notes.png"))
            report.images.append("review-notes.png")
            try await render(RecordingDetailView(model: model, recording: updated), width: 940, height: 710, scheme: .light,
                             to: directory.appendingPathComponent("review-workspace.png"))
            report.images.append("review-workspace.png")
            try await render(RecordingDetailView(model: model, recording: updated), width: 740, height: 590, scheme: .light,
                             to: directory.appendingPathComponent("review-small.png"))
            report.images.append("review-small.png")
            report.status = "passed"
            try checkpoint("Generated studio workflow completed")
            model.notice = "Studio check passed with generated content. No screen, camera, or microphone was captured."
        } catch {
            report.status = "failed"; report.error = error.localizedDescription
            try? checkpoint("Studio check failed")
            model.search = ""; model.errorMessage = error.localizedDescription
        }
    }

    private static func render<Content: View>(_ content: Content, width: Double, height: Double,
                                              scheme: ColorScheme, to destination: URL) async throws {
        // ImageRenderer omits macOS ScrollView and AppKit-backed controls. Mount our
        // generated fixture in an offscreen host and ask that view to draw itself.
        let host = NSHostingView(rootView: content.frame(width: width, height: height)
            .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, scheme))
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: width, height: height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(250))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw OpenLoomError.exportUnavailable
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw OpenLoomError.exportUnavailable }
        try data.write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}

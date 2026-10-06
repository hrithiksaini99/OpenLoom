import AppKit
@preconcurrency import AVFoundation
import Observation
import OpenLoomCore
import OSLog
@preconcurrency import ScreenCaptureKit

@MainActor @Observable
final class CaptureEngine: NSObject, SCContentSharingPickerObserver {
    private struct ScreenSegment {
        let stream: SCStream
        let output: SCRecordingOutput
        let observer: RecordingOutputObserver
        let streamObserver: CaptureStreamObserver
        let url: URL
    }
    private struct Segment {
        let token: UUID
        var screen: ScreenSegment?
        let cameraURL: URL?
        let cameraStartedAt: Double?
        let destination: URL
    }
    var phase: RecordingPhase = .idle {
        didSet { if phase != oldValue { onPhaseChange?() } }
    }
    var settings: RecordingSettings {
        didSet {
            if settings.mode != oldValue.mode {
                modeDidChange()
                onModeChange?()
            }
        }
    }
    var title = ""
    private(set) var processingMessage = ""
    private(set) var processingProgress: Double?
    private(set) var isCancellingProcessing = false
    let camera = CameraController()
    private(set) var dimensions: CaptureDimensions?
    private(set) var manifest: RecordingManifest?
    private(set) var lastInterruptedID: UUID?
    var onLibraryChange: (() -> Void)?
    var onFinish: ((UUID) -> Void)?
    var onNotice: ((String) -> Void)?
    var onPhaseChange: (() -> Void)?
    var onModeChange: (() -> Void)?
    private var screenLabel = "No screen selected"
    private var selectedFilter: SCContentFilter?
    private var segment: Segment?
    private var startToken = UUID()
    private let library: RecordingLibrary
    private let exporter: MediaExporter
    private var diskMonitor: Task<Void, Never>?
    private let clicks = ClickRecorder()
    private var processingTask: Task<Void, Never>?
    private var processingID = UUID()
    private let logger = Logger(subsystem: "org.openloom.local", category: "capture")

    init(library: RecordingLibrary, exporter: MediaExporter, settings: RecordingSettings) {
        self.library = library; self.exporter = exporter; self.settings = settings
        super.init()
        SCContentSharingPicker.shared.add(self)
        if settings.mode == .camera { phase = .ready }
        camera.onFailure = { [weak self] message in
            Task { @MainActor in
                guard let self, self.phase == .recording else { return }
                await self.fail(message)
            }
        }
        camera.onUnexpectedFinish = { [weak self] message in
            Task { @MainActor in
                guard let self, self.phase == .recording else { return }
                self.onNotice?("Camera stopped: \(message) Saving the completed take…")
                await self.stop()
            }
        }
    }
    var hasScreenSource: Bool { selectedFilter != nil }
    var canStart: Bool {
        phase == .ready && (!settings.mode.usesCamera || (!camera.isPreparing && !camera.requiresRestart && !camera.devices.isEmpty))
    }
    var sourceLabel: String {
        let name = camera.devices.first { $0.id == settings.cameraID }?.name ?? "Default camera"
        return switch settings.mode {
        case .screen: screenLabel
        case .screenAndCamera: "\(screenLabel) + \(name)"
        case .camera: name
        }
    }
    var elapsed: TimeInterval {
        let saved = manifest?.segmentDurations.reduce(0, +) ?? 0
        let active = segment?.screen?.output.recordedDuration.seconds ?? (segment?.cameraURL != nil ? camera.elapsed : 0)
        return saved + (active.isFinite ? max(0, active) : 0)
    }
    func modeDidChange() {
        guard !phase.isSessionActive else { return }
        updateReadyPhase()
        if !settings.mode.usesCamera { Task { await camera.stopPreview() } }
    }
    private func updateReadyPhase() { phase = settings.mode == .camera || selectedFilter != nil ? .ready : .idle }
    private func excludeStudioWindows(from filter: SCContentFilter) async throws -> SCContentFilter {
        guard filter.style == .display else { return filter }
        guard filter.includedDisplays.count == 1, let display = filter.includedDisplays.first else { throw OpenLoomError.invalidDimensions }
        let pid = ProcessInfo.processInfo.processIdentifier
        let ownApp: SCRunningApplication
        if let app = filter.includedApplications.first(where: { $0.processID == pid }) { ownApp = app }
        else {
            let content = try await AsyncDeadline.run(timeout: .seconds(10)) {
                try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            }
            guard let app = content.applications.first(where: { $0.processID == pid }) else { throw OpenLoomError.invalidDimensions }
            ownApp = app
        }
        // Keep precisely the user's selected display and exclude this application,
        // including floating panels created or moved after the source was selected.
        let safe = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
        safe.includeMenuBar = filter.includeMenuBar
        return safe
    }
    func chooseSource() {
        guard settings.mode.usesScreen, phase.canChooseSource, segment == nil else { return }
        phase = .choosingSource
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleDisplay, .singleWindow]
        configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier ?? "org.openloom.local"]
        configuration.allowsChangingSelectedContent = false
        picker.defaultConfiguration = configuration
        picker.isActive = true
        picker.present()
    }
    /// Diagnostic entry point is restricted to the test window owned by this process.
    func selectAcceptanceSource(_ window: SCWindow, expectedWindowID: CGWindowID) throws {
        guard ProcessInfo.processInfo.arguments.contains("--screen-lifecycle-check"),
              window.windowID == expectedWindowID,
              window.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier,
              !phase.isSessionActive, !settings.mode.usesCamera else { throw OpenLoomError.unsafePath }
        selectedFilter = SCContentFilter(desktopIndependentWindow: window)
        screenLabel = "Generated test window"
        updateReadyPhase()
    }
    func cancelCountdown() {
        guard manifest == nil else { return }
        switch phase {
        case .countdown, .starting: startToken = UUID(); updateReadyPhase()
        default: break
        }
    }
    func start() async {
        guard canStart else { return }
        let token = UUID()
        startToken = token
        lastInterruptedID = nil
        phase = .starting
        do {
            let snapshot = settings
            let filter = snapshot.mode.usesScreen ? selectedFilter : nil
            guard !snapshot.mode.usesScreen || filter != nil else { throw OpenLoomError.invalidDimensions }
            try snapshot.validate()
            try library.checkFreeSpace()
            if snapshot.mode.usesCamera {
                try await camera.authorize()
                guard startToken == token else { return }
            }
            if snapshot.microphone {
                let allowed = await AVCaptureDevice.requestAccess(for: .audio)
                guard startToken == token else { return }
                guard allowed, AVCaptureDevice.default(for: .audio) != nil else { throw OpenLoomError.microphoneDenied }
            }
            if let filter {
                dimensions = try CaptureDimensions.fit(width: filter.contentRect.width * Double(filter.pointPixelScale),
                                                      height: filter.contentRect.height * Double(filter.pointPixelScale), preset: snapshot.resolution)
            }
            if snapshot.countdownSeconds > 0 {
                for count in stride(from: snapshot.countdownSeconds, through: 1, by: -1) {
                    guard startToken == token else { return }
                    phase = .countdown(count)
                    try await Task.sleep(for: .seconds(1))
                }
            }
            guard startToken == token else { return }
            phase = .starting
            let defaultTitle = "Recording \(Date.now.formatted(date: .abbreviated, time: .shortened))"
            manifest = try library.create(title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultTitle : title,
                                          source: sourceLabel, settings: snapshot)
            onLibraryChange?()
            try await beginSegment(filter: filter, settings: snapshot)
            phase = .recording
            beginClickCapture(filter: filter)
            startDiskMonitor()
        } catch {
            guard startToken == token else { return }
            await fail(error.localizedDescription)
        }
    }
    func pause() async {
        guard phase == .recording else { return }
        phase = .pausing
        diskMonitor?.cancel(); clicks.stop()
        let token = beginProcessing("Finishing capture files…")
        let task = Task { [self] in
            defer { endProcessing(token) }
            do {
                try await finishSegment()
                try Task.checkCancellation()
                phase = .paused
                logger.info("Pause saved source checkpoint")
                onLibraryChange?()
            } catch { await fail(error is CancellationError ? "Processing cancelled. Source files were kept for recovery." : error.localizedDescription) }
        }
        processingTask = task
        await task.value
    }
    func resume() async {
        guard phase == .paused, let manifest else { return }
        phase = .starting
        do {
            try library.checkFreeSpace()
            try await beginSegment(filter: manifest.settings.mode.usesScreen ? selectedFilter : nil, settings: manifest.settings)
            phase = .recording
            beginClickCapture(filter: selectedFilter)
            startDiskMonitor()
        } catch { await fail(error.localizedDescription) }
    }
    func addChapter() {
        guard (phase == .recording || phase == .paused), var updated = manifest else { return }
        let count = updated.notes.filter { $0.kind == .chapter }.count + 1
        updated.notes.append(TimedNote(time: elapsed, text: "Chapter \(count)", kind: .chapter))
        do { try library.save(updated); manifest = updated; onLibraryChange?() }
        catch { Task { await fail(error.localizedDescription) } }
    }
    func stop() async {
        guard phase == .recording || phase == .paused else { return }
        let wasRecording = phase == .recording
        phase = .finishing
        diskMonitor?.cancel(); clicks.stop()
        let token = beginProcessing("Finishing capture files…")
        let task = Task { [self] in
            defer { endProcessing(token) }
            do {
                if wasRecording { try await finishSegment() }
                try Task.checkCancellation()
                guard let current = manifest else { throw OpenLoomError.noMedia }
                let progress: RecordingProgress = { [weak self] message, fraction in
                    await MainActor.run { self?.reportProcessing(message, fraction: fraction, token: token) }
                }
                let finished = try await AsyncDeadline.run(timeout: .seconds(max(180, current.duration * 20 + 60))) { [exporter, library] in
                    try await exporter.finalize(recording: current, library: library, progress: progress)
                }
                completeSavedRecording(finished.id)
                logger.info("Stop completed local video")
            } catch { await fail(error is CancellationError ? "Processing cancelled. Source files were kept for recovery." : error.localizedDescription) }
        }
        processingTask = task
        await task.value
    }

    func cancelProcessing() {
        guard phase.isProcessing, !isCancellingProcessing else { return }
        isCancellingProcessing = true
        processingMessage = "Stopping processing; keeping source files…"
        logger.notice("User cancelled processing")
        processingTask?.cancel()
    }
    func cancelProcessingAndWait() async { let task = processingTask; cancelProcessing(); await task?.value }
    private func beginProcessing(_ message: String) -> UUID {
        processingID = UUID()
        processingMessage = message; processingProgress = nil; isCancellingProcessing = false
        logger.info("Processing capture files")
        return processingID
    }
    private func reportProcessing(_ message: String, fraction: Double?, token: UUID) {
        guard processingID == token, phase.isProcessing, !isCancellingProcessing else { return }
        if processingMessage != message { logger.info("Processing stage: \(message, privacy: .public)") }
        processingMessage = message; processingProgress = fraction
    }
    private func endProcessing(_ token: UUID) {
        guard processingID == token else { return }
        processingTask = nil; processingMessage = ""; processingProgress = nil; isCancellingProcessing = false
    }
    private func beginSegment(filter: SCContentFilter?, settings: RecordingSettings) async throws {
        guard let manifest else { throw OpenLoomError.invalidManifest }
        let index = manifest.segmentDurations.count
        let destination = try library.segmentURL(for: manifest.id, index: index)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw OpenLoomError.invalidSegment }
        let token = UUID()
        let cameraURL = settings.mode.usesCamera ? try library.captureURL(for: manifest.id, index: index, camera: true) : nil
        let cameraStart: Double?
        if let cameraURL {
            guard !FileManager.default.fileExists(atPath: cameraURL.path) else { throw OpenLoomError.invalidSegment }
            cameraStart = try await camera.start(settings: settings, destination: cameraURL)
        } else { cameraStart = nil }
        segment = Segment(token: token, cameraURL: cameraURL, cameraStartedAt: cameraStart, destination: destination)
        guard settings.mode.usesScreen else { try journalCamera(index: index, offset: 0); return }
        guard let filter, let size = dimensions else { throw OpenLoomError.invalidDimensions }
        let url = settings.mode.usesCamera ? try library.captureURL(for: manifest.id, index: index, camera: false) : destination
        guard !FileManager.default.fileExists(atPath: url.path) else { throw OpenLoomError.invalidSegment }
        let config = SCStreamConfiguration()
        config.width = size.width; config.height = size.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.framesPerSecond))
        config.queueDepth = 3; config.showsCursor = settings.showsCursor
        config.capturesAudio = settings.systemAudio; config.excludesCurrentProcessAudio = true
        config.captureMicrophone = settings.microphone
        config.microphoneCaptureDeviceID = settings.microphone ? AVCaptureDevice.default(for: .audio)?.uniqueID : nil
        config.sampleRate = 48_000; config.channelCount = 2; config.ignoreShadowsSingleWindow = true
        let recordingConfig = SCRecordingOutputConfiguration()
        recordingConfig.outputURL = url; recordingConfig.outputFileType = .mp4
        recordingConfig.videoCodecType = settings.codec == .h264 ? .h264 : .hevc
        guard recordingConfig.availableVideoCodecTypes.contains(recordingConfig.videoCodecType),
              recordingConfig.availableOutputFileTypes.contains(.mp4) else { throw OpenLoomError.exportUnavailable }
        let observer = RecordingOutputObserver(), streamObserver = CaptureStreamObserver()
        let onFailure: (String) -> Void = { [weak self] message in
            Task { @MainActor in
                guard let self, self.segment?.token == token, self.phase == .recording else { return }
                await self.fail(message)
            }
        }
        observer.onFailure = onFailure; streamObserver.onStop = onFailure
        let stream = SCStream(filter: filter, configuration: config, delegate: streamObserver)
        let output = SCRecordingOutput(configuration: recordingConfig, delegate: observer)
        try stream.addRecordingOutput(output)
        segment?.screen = ScreenSegment(stream: stream, output: output, observer: observer, streamObserver: streamObserver, url: url)
        do {
            try await AsyncDeadline.run(timeout: .seconds(15)) { @MainActor in
                try await stream.startCapture()
                try await observer.waitForStart()
            }
        } catch { observer.timeOut(); throw error }
        if let cameraStart {
            try journalCamera(index: index, offset: cameraStart - (observer.startedAt ?? cameraStart))
        }
    }
    private func journalCamera(index: Int, offset: Double) throws {
        guard var current = manifest, current.settings.mode.usesCamera else { return }
        current.cameraSegments.removeAll { $0.index == index }
        current.cameraSegments.append(CameraSegmentCheckpoint(index: index, offset: offset))
        try library.save(current)
        manifest = current
    }
    private func finishSegment() async throws {
        guard let current = segment, var updated = manifest else { throw OpenLoomError.noMedia }
        let cameraFinish = current.cameraURL.map { _ in Task { try await camera.stop() } }
        if let screen = current.screen {
            do {
                try await AsyncDeadline.run(timeout: .seconds(30)) { @MainActor in
                    try await screen.stream.stopCapture()
                    try await screen.observer.waitForFinish()
                }
            } catch { screen.observer.timeOut(); cameraFinish?.cancel(); throw error }
        }
        try await cameraFinish?.value
        try Task.checkCancellation()
        reportProcessing("Checking saved source files…", fraction: nil, token: processingID)
        let durationURL: URL
        if let cameraURL = current.cameraURL {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cameraURL.path)
            if let screen = current.screen {
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: screen.url.path)
                durationURL = screen.url
            } else { durationURL = cameraURL }
        } else { durationURL = current.destination }
        let duration = try await exporter.duration(of: durationURL)
        try Task.checkCancellation()
        if current.cameraURL == nil { try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: current.destination.path) }
        updated.segmentDurations.append(duration)
        updated.duration = updated.segmentDurations.reduce(0, +)
        try library.save(updated)
        manifest = updated; segment = nil
        logger.info("Saved finalized source checkpoint")
    }
    private func fail(_ reason: String) async {
        phase = .finishing
        diskMonitor?.cancel(); clicks.stop()
        // Cleanup gets a fresh cancellation scope; it is bounded even if a framework never replies.
        let cleanup = Task { @MainActor [self] in
            if let screen = segment?.screen {
                screen.observer.onFailure = nil; screen.streamObserver.onStop = nil
                screen.observer.timeOut()
                _ = try? await AsyncDeadline.run(timeout: .seconds(3)) { @MainActor in try await screen.stream.stopCapture() }
            }
            await camera.shutdown()
        }
        await cleanup.value
        segment = nil
        if var interrupted = manifest {
            // Finalization may have journaled additional takes or committed the MP4
            // immediately before cancellation. Never replace that with a stale snapshot.
            if let latest = try? library.load(interrupted.id) {
                if latest.status == .ready {
                    completeSavedRecording(latest.id)
                    onNotice?("The recording finished saving before processing was interrupted.")
                    return
                }
                if latest.segmentDurations.count > interrupted.segmentDurations.count { interrupted = latest }
            }
            lastInterruptedID = interrupted.id
            interrupted.status = .interrupted; try? library.save(interrupted)
        }
        manifest = nil; selectedFilter = nil; screenLabel = "No screen selected"
        SCContentSharingPicker.shared.isActive = false
        phase = .failed(reason)
        logger.error("Capture operation failed; source files retained")
        onLibraryChange?()
        NSApp.activate(ignoringOtherApps: true)
    }
    private func completeSavedRecording(_ id: UUID) {
        manifest = nil; selectedFilter = nil; screenLabel = "No screen selected"; title = ""
        SCContentSharingPicker.shared.isActive = false
        phase = settings.mode == .camera ? .ready : .idle
        onLibraryChange?(); onFinish?(id)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func beginClickCapture(filter: SCContentFilter?) {
        guard manifest?.settings.captureClicks == true, manifest?.settings.mode.usesScreen == true, let filter else { return }
        clicks.start(filter: filter) { [weak self] point in
            guard let self, self.phase == .recording, var updated = self.manifest, updated.clicks.count < 100_000 else { return }
            updated.clicks.append(CursorClick(time: self.elapsed, point: point))
            self.manifest = updated
        }
    }
    private func startDiskMonitor() {
        diskMonitor?.cancel()
        diskMonitor = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                guard let self, self.phase == .recording else { return }
                do { try self.library.checkFreeSpace() } catch {
                    self.onNotice?("Recording stopped because disk space is low. Saving the completed take…")
                    await self.stop(); return
                }
            }
        }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor [weak self] in
            guard let self, self.phase == .choosingSource else { return }
            self.updateReadyPhase()
        }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor [weak self] in
            guard let self, self.phase == .choosingSource else { return }
            do {
                let safe = try await self.excludeStudioWindows(from: filter)
                guard self.phase == .choosingSource else { return }
                self.selectedFilter = safe
                self.screenLabel = filter.style == .display ? "Selected display" : "Selected window"
                self.phase = .ready
            } catch {
                guard self.phase == .choosingSource else { return }
                self.phase = .failed("Could not prepare capture with studio windows excluded: \(error.localizedDescription)")
            }
        }
    }
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.phase = .failed(message) }
    }
}

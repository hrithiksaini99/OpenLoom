import AppKit
import Foundation
import Observation
import OpenLoomCore

@MainActor @Observable
final class AppModel {
    let library: RecordingLibrary
    let exporter: MediaExporter
    let recorder: CaptureEngine
    let floating = FloatingRecorderController()
    @ObservationIgnored var openStudioWindow: (() -> Void)?
    let transcriber = LocalTranscriber()
    private(set) var recordings: [RecordingManifest] = []
    var selectedID: UUID?
    var search = ""
    var errorMessage: String?
    var libraryWarning: String?
    var quitRequested = false
    var isRecovering = false
    var recoveryProgress = ""
    var recoveryFraction: Double?
    private var recoveryTask: Task<Void, Never>?
    private(set) var isExporting = false
    private(set) var exportProgress = ""
    private(set) var exportFraction: Double?
    private var exportTask: Task<URL, any Error>?
    private var exportID = UUID()
    var isRunningCameraCheck = false
    var isRunningScreenCheck = false
    var isRunningUICheck = false
    @ObservationIgnored var acceptancePlayer: PlaybackController?
    var notice: String?
    private(set) var isTranscribing = false
    private(set) var transcriptionID: UUID?
    private(set) var speechLanguages: [SpeechLanguage] = []
    var speechLanguage = ""
    var transcriptionProgress = ""
    private var transcriptionTask: Task<Void, Never>?

    init() {
        let library = RecordingLibrary(root: RecordingLibrary.defaultRoot)
        let exporter = MediaExporter()
        var settings = RecordingSettings()
        if let data = UserDefaults.standard.data(forKey: "recordingSettings"),
           let stored = try? JSONDecoder().decode(RecordingSettings.self, from: data),
           (try? stored.validate()) != nil { settings = stored }
        self.library = library
        self.exporter = exporter
        self.recorder = CaptureEngine(library: library, exporter: exporter, settings: settings)
        recorder.onLibraryChange = { [weak self] in self?.refresh() }
        recorder.onFinish = { [weak self] id in self?.selectedID = id; self?.showLibrary() }
        recorder.onNotice = { [weak self] message in self?.notice = message }
        recorder.onPhaseChange = { [weak self] in
            guard let self else { return }
            self.floating.sync(model: self)
        }
        recorder.onModeChange = { [weak self] in
            guard let self else { return }
            if !self.recorder.settings.mode.usesCamera { self.floating.hideCamera() }
            self.floating.sync(model: self)
        }
        refresh()
        Task { await refreshSpeechLanguages() }
    }

    var filteredRecordings: [RecordingManifest] {
        recordings.filter {
            search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                || $0.transcript?.plainText.localizedCaseInsensitiveContains(search) == true
                || $0.notes.contains { $0.text.localizedCaseInsensitiveContains(search) }
        }
    }

    var selected: RecordingManifest? { recordings.first { $0.id == selectedID } }
    var isBusy: Bool { isRunningCameraCheck || isRunningScreenCheck || recorder.phase.isSessionActive || isRecovering || isExporting || isTranscribing }

    func refresh() {
        do {
            let snapshot = try library.scan()
            recordings = snapshot.recordings
            libraryWarning = snapshot.warnings.first
            if let selectedID, !recordings.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
        } catch { errorMessage = error.localizedDescription }
    }

    func saveSettings() {
        guard !isRunningCameraCheck, !isRunningScreenCheck, !isRunningUICheck else { return }
        if let data = try? JSONEncoder().encode(recorder.settings) { UserDefaults.standard.set(data, forKey: "recordingSettings") }
    }

    func showLibrary() { openStudioWindow?(); NSApp.activate(ignoringOtherApps: true) }

    func toggleFloatingCamera() async {
        if floating.isCameraVisible { await hideFloatingCamera(); return }
        if !recorder.settings.mode.usesCamera {
            guard !recorder.phase.isSessionActive else { return }
            recorder.settings.mode = .screenAndCamera
        }
        if recorder.camera.isRecording {
            await recorder.camera.setRecordingPreview(true)
        } else { await recorder.camera.preview(settings: recorder.settings) }
        guard recorder.camera.isPreviewing || recorder.camera.isShowingRecordingPreview else {
            errorMessage = recorder.camera.errorMessage; return
        }
        floating.showCamera(model: self)
    }

    func hideFloatingCamera() async {
        floating.hideCamera()
        if recorder.camera.isRecording { await recorder.camera.setRecordingPreview(false) }
        else { await recorder.camera.stopPreview() }
    }

    func revealLibrary() {
        do {
            try library.prepare()
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: library.root.path)
        } catch { errorMessage = error.localizedDescription }
    }

    func reveal(_ url: URL) {
        do {
            try LocalFilePolicy.requireContained(url, in: library.root)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch { errorMessage = error.localizedDescription }
    }

    func rename(_ recording: RecordingManifest, to title: String) {
        guard recorder.manifest?.id != recording.id else { return }
        do { try library.rename(recording, to: title); refresh() }
        catch { errorMessage = error.localizedDescription }
    }

    func recover(_ recording: RecordingManifest, includeCamera: Bool = true) async {
        guard !isBusy, recording.status != .ready else { return }
        isRecovering = true
        recoveryProgress = "Checking saved source files…"; recoveryFraction = nil
        let task = Task { [self] in
            defer { isRecovering = false; recoveryTask = nil; recoveryProgress = ""; recoveryFraction = nil }
            do {
                let progress: RecordingProgress = { [weak self] message, fraction in
                    await MainActor.run {
                        guard let self, self.isRecovering else { return }
                        self.recoveryProgress = message; self.recoveryFraction = fraction
                    }
                }
                _ = try await AsyncDeadline.run(timeout: .seconds(max(180, recording.duration * 20 + 60))) { [exporter, library] in
                    try await exporter.finalize(recording: recording, library: library, includeCamera: includeCamera, progress: progress)
                }
                try Task.checkCancellation()
                notice = includeCamera ? "Recovered the saved recording." : "Recovered the screen without its camera overlay. Camera sources remain in the session folder."
                refresh()
            } catch {
                refresh()
                errorMessage = error is CancellationError ? "Recovery cancelled. Source files were kept; you can retry." : error.localizedDescription
            }
        }
        recoveryTask = task
        await task.value
    }
    func cancelRecovery() { recoveryTask?.cancel() }
    func cancelRecoveryAndWait() async { let task = recoveryTask; task?.cancel(); await task?.value }

    func refreshSpeechLanguages() async {
        speechLanguages = await transcriber.installedLanguages()
        if !speechLanguages.contains(where: { $0.id == speechLanguage }) { speechLanguage = speechLanguages.first?.id ?? "" }
    }

    func generateCaptions(_ recording: RecordingManifest) {
        guard !isBusy, recording.status == .ready else { return }
        guard !speechLanguage.isEmpty else { errorMessage = OpenLoomError.speechUnavailable.localizedDescription; return }
        isTranscribing = true
        transcriptionID = recording.id
        transcriptionProgress = "Preparing audio on this Mac…"
        let language = speechLanguage
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            var audio: URL?
            defer {
                if let audio { try? FileManager.default.removeItem(at: audio) }
                self.isTranscribing = false; self.transcriptionID = nil
                self.transcriptionTask = nil; self.transcriptionProgress = ""
            }
            do {
                let input = self.library.outputURL(for: recording.id)
                try LocalFilePolicy.requireContained(input, in: self.library.root)
                let destination = try self.library.newExportURL(for: recording.id, name: "speech", extension: "m4a")
                audio = destination
                try await self.exporter.extractSpeechAudio(input: input, destination: destination)
                self.transcriptionProgress = "Transcribing locally…"
                let transcript = try await self.transcriber.transcribe(audio: destination, language: language, duration: recording.duration) { [weak self] seconds in
                    await MainActor.run { self?.transcriptionProgress = "Transcribed through \(Formatters.duration(seconds))" }
                }
                try Task.checkCancellation()
                try self.updateRecording(recording.id) { $0.transcript = transcript }
                self.notice = transcript.cues.isEmpty ? "No speech was detected in this recording." : "Local captions are ready."
            } catch is CancellationError { self.notice = "Caption generation cancelled."
            } catch { self.errorMessage = error.localizedDescription }
        }
    }

    func cancelTranscription() { transcriptionTask?.cancel() }

    func createDemo() async {
        guard !isBusy else { return }
        isExporting = true
        defer { isExporting = false }
        var demo: RecordingManifest?
        do {
            var settings = RecordingSettings()
            settings.resolution = .hd720; settings.systemAudio = false; settings.microphone = false
            var recording = try library.create(title: "Local demo · generated video & sample captions",
                                               source: "Generated frames · no screen, camera, or audio capture", settings: settings)
            demo = recording
            let segment = try library.segmentURL(for: recording.id, index: 0)
            try await LocalDemoGenerator().write(to: segment)
            recording.segmentDurations = [try await exporter.duration(of: segment)]
            recording.duration = try await exporter.assemble(segments: [segment], destination: library.outputURL(for: recording.id))
            recording.transcript = LocalTranscript(localeIdentifier: "en-US", cues: [
                TranscriptCue(start: 0, end: 2, text: "This sample video is generated locally."),
                TranscriptCue(start: 2, end: 4, text: "Click on chapters to jump between moments."),
                TranscriptCue(start: 4, end: 6, text: "Add a timed drawing, highlight, or zoom."),
            ], engine: "Generated sample captions · no speech recognition used")
            recording.notes = [
                TimedNote(time: 0, text: "Record", kind: .chapter), TimedNote(time: 2, text: "Review", kind: .chapter),
                TimedNote(time: 4, text: "Polish", kind: .chapter), TimedNote(time: 5, text: "Try adding your own timestamped note.", kind: .note),
            ]
            recording.clicks = [CursorClick(time: 2.4, point: .init(x: 0.65, y: 0.4)), CursorClick(time: 4.6, point: .init(x: 0.25, y: 0.5))]
            recording.status = .ready
            try library.save(recording); refresh(); selectedID = recording.id
            notice = "Demo generated locally. Its captions and click positions are samples."
        } catch {
            if var demo { demo.status = .interrupted; try? library.save(demo); refresh() }
            errorMessage = error.localizedDescription
        }
    }

    func saveNote(for id: UUID, noteID: UUID? = nil, time: Double, text: String, kind: NoteKind) {
        do {
            try updateRecording(id) { recording in
                let note = TimedNote(id: noteID ?? UUID(), time: min(max(0, time), recording.duration),
                                     text: text.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind)
                if let index = recording.notes.firstIndex(where: { $0.id == note.id }) { recording.notes[index] = note }
                else { recording.notes.append(note) }
                recording.notes.sort { $0.time < $1.time }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func removeNote(for id: UUID, noteID: UUID) {
        do { try updateRecording(id) { $0.notes.removeAll { $0.id == noteID } } }
        catch { errorMessage = error.localizedDescription }
    }

    func saveEdits(for id: UUID, edits: [VisualCue]) throws {
        try updateRecording(id) { $0.visualEdits = edits }
    }

    func saveCaption(for id: UUID, cue: TranscriptCue) {
        do {
            try updateRecording(id) { recording in
                guard let index = recording.transcript?.cues.firstIndex(where: { $0.id == cue.id }) else { return }
                recording.transcript?.cues[index] = cue
                recording.transcript?.cues.sort { $0.start < $1.start }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func exportCaptions(_ recording: RecordingManifest) {
        do {
            let urls = try library.exportCaptions(recording)
            notice = "SRT and WebVTT saved in this recording’s exports folder."
            if let url = urls.first { reveal(url) }
        } catch { errorMessage = error.localizedDescription }
    }

    func exportReview(_ recording: RecordingManifest) {
        do { let url = try library.exportReview(recording); notice = "Review document saved locally."; reveal(url) }
        catch { errorMessage = error.localizedDescription }
    }

    func exportPolished(_ recording: RecordingManifest, edits: [VisualCue], revealResult: Bool = true) async {
        guard !isBusy else { return }
        do {
            try saveEdits(for: recording.id, edits: edits)
            let input = library.outputURL(for: recording.id)
            try LocalFilePolicy.requireContained(input, in: library.root)
            let destination = try library.newExportURL(for: recording.id, name: "polished")
            _ = try await performVideoExport("Rendering edited video…", duration: recording.duration) { [exporter] progress in
                _ = try await exporter.polish(input: input, edits: edits, settings: recording.settings, destination: destination, progress: progress)
                return destination
            }
            notice = "Polished MP4 saved locally. Your original is preserved."
            if revealResult { reveal(destination) }
        } catch is CancellationError { notice = "Video export cancelled. Your original and edits were kept."
        } catch { errorMessage = error.localizedDescription }
    }

    func exportTrim(_ recording: RecordingManifest, start: Double, end: Double) async throws -> URL {
        try library.checkFreeSpace()
        let input = library.outputURL(for: recording.id)
        try LocalFilePolicy.requireContained(input, in: library.root)
        let destination = try library.newExportURL(for: recording.id)
        return try await performVideoExport("Exporting trimmed video…", duration: end - start) { [exporter] progress in
            try await exporter.trim(input: input, start: start, end: end, destination: destination, progress: progress)
            return destination
        }
    }

    var canCancelExport: Bool { exportTask != nil }
    func cancelExport() { exportTask?.cancel() }
    func cancelExportAndWait() async { let task = exportTask; task?.cancel(); _ = try? await task?.value }

    private func performVideoExport(_ message: String, duration: Double,
                                    operation: @escaping @Sendable (MediaProgress?) async throws -> URL) async throws -> URL {
        guard !isBusy else { throw OpenLoomError.recordingFailed("Finish or cancel the current local task first.") }
        isExporting = true; exportProgress = message; exportFraction = nil
        let token = UUID(); exportID = token
        let progress: MediaProgress = { [weak self] fraction in
            await MainActor.run {
                guard let self, self.exportID == token, self.exportTask?.isCancelled == false else { return }
                self.exportFraction = fraction
            }
        }
        let task = Task { [self] in
            defer {
                if exportID == token { isExporting = false; exportTask = nil; exportProgress = ""; exportFraction = nil }
            }
            return try await AsyncDeadline.run(timeout: .seconds(max(180, duration * 20 + 60))) { try await operation(progress) }
        }
        exportTask = task
        return try await task.value
    }

    private func updateRecording(_ id: UUID, mutation: (inout RecordingManifest) -> Void) throws {
        guard var recording = recordings.first(where: { $0.id == id }), recording.status == .ready,
              recorder.manifest?.id != id else { throw OpenLoomError.invalidReview }
        mutation(&recording)
        try library.save(recording)
        refresh()
    }
}

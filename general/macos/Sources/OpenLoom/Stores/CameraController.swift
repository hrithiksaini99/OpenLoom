@preconcurrency import AVFoundation
import Observation
import OpenLoomCore

@MainActor @Observable
final class CameraController {
    private let recorder = CameraRecorder()
    private(set) var devices: [CameraDevice] = CameraRecorder.devices()
    private(set) var isPreviewing = false
    private(set) var isRecording = false
    private(set) var isShowingRecordingPreview = false
    private(set) var isPreparing = false
    private(set) var format: CameraFormatInfo?
    private(set) var startedAt: Double?
    private(set) var previewFrame: CGImage?
    private(set) var requiresRestart = false
    var errorMessage: String?
    var onFailure: ((String) -> Void)?
    var onUnexpectedFinish: ((String) -> Void)?
    private var previewToken = UUID()
    private var wantsRecordingPreview = false
    var elapsed: Double { startedAt.map { max(0, CMClockGetTime(CMClockGetHostTimeClock()).seconds - $0) } ?? 0 }

    init() {
        recorder.setFailureHandler { [weak self] message in
            Task { @MainActor in self?.onFailure?(message) }
        }
        recorder.setUnexpectedFinishHandler { [weak self] message in
            Task { @MainActor in self?.onUnexpectedFinish?(message) }
        }
        recorder.setPreviewHandler { [weak self] frame in
            Task { @MainActor in
                guard let self, self.isPreviewing || self.isShowingRecordingPreview else { return }
                self.previewFrame = frame
            }
        }
    }

    func refreshDevices() { devices = CameraRecorder.devices() }

    func authorize() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            let granted = try await AsyncDeadline.run(timeout: .seconds(60)) {
                await AVCaptureDevice.requestAccess(for: .video)
            }
            guard granted else { throw OpenLoomError.cameraDenied }
        case .denied, .restricted: throw OpenLoomError.cameraDenied
        @unknown default: throw OpenLoomError.cameraDenied
        }
        refreshDevices()
        guard !devices.isEmpty else { throw OpenLoomError.cameraUnavailable }
    }

    func preview(settings: RecordingSettings) async {
        guard !isPreparing, !isRecording, !requiresRestart else { return }
        isPreparing = true
        let token = UUID()
        previewToken = token
        defer { isPreparing = false }
        do {
            try await authorize()
            guard previewToken == token, !isRecording else { return }
            format = try await AsyncDeadline.run(timeout: .seconds(15)) { [recorder] in
                try await recorder.prepare(settings: settings, includeMicrophone: false, preview: true)
            }
            guard previewToken == token, !isRecording else { await endSession(); return }
            try await AsyncDeadline.run(timeout: .seconds(15)) { [recorder] in await recorder.startSession() }
            guard previewToken == token, !isRecording else { await endSession(); return }
            isPreviewing = true
            wantsRecordingPreview = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription; isPreviewing = false
            recorder.disablePreviewFrames(); previewFrame = nil
            await endSession()
        }
    }

    func stopPreview() async {
        guard !isRecording else { return }
        previewToken = UUID()
        isPreviewing = false
        wantsRecordingPreview = false
        recorder.disablePreviewFrames()
        previewFrame = nil
        await endSession()
    }

    func start(settings: RecordingSettings, destination: URL) async throws -> Double {
        guard !requiresRestart else { throw OpenLoomError.recordingFailed(errorMessage ?? "Restart OpenLoom before recording with the camera.") }
        previewToken = UUID()
        isPreparing = true
        defer { isPreparing = false }
        isPreviewing = false
        recorder.disablePreviewFrames()
        previewFrame = nil
        format = try await AsyncDeadline.run(timeout: .seconds(15)) { [recorder] in
            try await recorder.prepare(settings: settings, includeMicrophone: settings.mode == .camera && settings.microphone, preview: false)
        }
        let start = try await AsyncDeadline.run(timeout: .seconds(15)) { [recorder] in try await recorder.startRecording(to: destination) }
        isRecording = true
        startedAt = start
        if wantsRecordingPreview { await setRecordingPreview(true) }
        return start
    }

    func setRecordingPreview(_ enabled: Bool) async {
        guard isRecording else { return }
        let available: Bool
        do { available = try await AsyncDeadline.run(timeout: .seconds(5)) { [recorder] in await recorder.setPreviewEnabled(enabled) } }
        catch { errorMessage = "Camera preview did not respond. Your recording can still be stopped and saved."; return }
        isShowingRecordingPreview = enabled && available
        wantsRecordingPreview = enabled && available
        if !isShowingRecordingPreview { previewFrame = nil }
        if enabled && !available { errorMessage = "This camera cannot provide a preview while recording." }
    }

    func stop() async throws {
        guard isRecording else { return }
        defer { isRecording = false; isShowingRecordingPreview = false; previewFrame = nil; startedAt = nil }
        do {
            try await AsyncDeadline.run(timeout: .seconds(30)) { [recorder] in try await recorder.stopRecording() }
            await endSession()
        } catch { await endSession(); throw error }
    }

    func shutdown() async {
        previewToken = UUID()
        recorder.disablePreviewFrames()
        previewFrame = nil
        _ = try? await AsyncDeadline.run(timeout: .seconds(5)) { [recorder] in try await recorder.stopRecording() }
        await endSession()
        isRecording = false; isPreviewing = false; isShowingRecordingPreview = false; previewFrame = nil; startedAt = nil
    }

    private func endSession() async {
        do {
            let released = try await AsyncDeadline.run(timeout: .seconds(5)) { [recorder] in await recorder.stopSession() }
            guard released else { throw OpenLoomError.finishTimedOut }
        } catch {
            requiresRestart = true
            errorMessage = "The camera did not release promptly. Source files were kept. Restart OpenLoom before using the camera again."
        }
    }
}

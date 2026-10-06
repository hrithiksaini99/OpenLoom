@preconcurrency import AVFoundation
import Foundation
import OpenLoomCore

struct CameraDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

struct CameraFormatInfo: Sendable {
    let width: Int
    let height: Int
    let framesPerSecond: Int
}

/// All mutable capture state belongs to queue. Views receive images, never this session.
final class CameraRecorder: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "org.openloom.camera", qos: .userInitiated)
    private let output = AVCaptureMovieFileOutput()
    private let previewOutput = AVCaptureVideoDataOutput()
    private let previewFrames = CameraPreviewFrames()
    private let previewQueue = DispatchQueue(label: "org.openloom.camera-preview", qos: .userInitiated)
    private var startWaiter: CheckedContinuation<Double, any Error>?
    private var finishWaiter: CheckedContinuation<Void, any Error>?
    private var currentURL: URL?
    private var finished: Result<Void, any Error>?
    private var onFailure: (@Sendable (String) -> Void)?
    private var onUnexpectedFinish: (@Sendable (String) -> Void)?

    func setFailureHandler(_ handler: @escaping @Sendable (String) -> Void) { queue.async { self.onFailure = handler } }
    func setUnexpectedFinishHandler(_ handler: @escaping @Sendable (String) -> Void) { queue.async { self.onUnexpectedFinish = handler } }
    func setPreviewHandler(_ handler: @escaping @Sendable (CGImage) -> Void) { previewFrames.setHandler(handler) }
    func disablePreviewFrames() { previewFrames.setEnabled(false) }
    func setPreviewEnabled(_ enabled: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                guard self.previewOutput.connection(with: .video) != nil else { continuation.resume(returning: false); return }
                // Changing a connection's isEnabled while a movie is recording
                // rebuilds the macOS capture graph and can end the take. Keep
                // the graph fixed; only gate image generation in the delegate.
                self.previewFrames.setEnabled(enabled)
                continuation.resume(returning: true)
            }
        }
    }

    static func devices() -> [CameraDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external],
                                         mediaType: .video, position: .unspecified).devices
            .filter { !$0.isContinuityCamera }
            .map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    func prepare(settings: RecordingSettings, includeMicrophone: Bool, preview: Bool = false) async throws -> CameraFormatInfo {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard !self.output.isRecording else { throw OpenLoomError.cameraUnavailable }
                    if self.session.isRunning { self.session.stopRunning() }
                    let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external],
                                                                   mediaType: .video, position: .unspecified).devices.filter { !$0.isContinuityCamera }
                    let selected: AVCaptureDevice?
                    if let id = settings.cameraID { selected = devices.first { $0.uniqueID == id } }
                    else { selected = devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? devices.first }
                    guard let device = selected else { throw OpenLoomError.cameraUnavailable }
                    let camera = try AVCaptureDeviceInput(device: device)
                    self.session.beginConfiguration()
                    defer { self.session.commitConfiguration() }
                    for input in self.session.inputs { self.session.removeInput(input) }
                    for output in self.session.outputs { self.session.removeOutput(output) }
                    self.previewFrames.setEnabled(preview)
                    let resolution: ResolutionPreset = settings.mode == .screenAndCamera ? .hd720 : settings.resolution
                    let preset: AVCaptureSession.Preset = switch resolution {
                    case .hd720: .hd1280x720
                    case .hd1080: .hd1920x1080
                    case .uhd4K: .hd4K3840x2160
                    }
                    if self.session.canSetSessionPreset(preset) { self.session.sessionPreset = preset }
                    else { self.session.sessionPreset = .high }
                    guard self.session.canAddInput(camera) else { throw OpenLoomError.cameraUnavailable }
                    self.session.addInput(camera)
                    if includeMicrophone {
                        guard let mic = AVCaptureDevice.default(for: .audio) else { throw OpenLoomError.microphoneDenied }
                        let audio = try AVCaptureDeviceInput(device: mic)
                        guard self.session.canAddInput(audio) else { throw OpenLoomError.microphoneDenied }
                        self.session.addInput(audio)
                    }
                    guard self.session.canAddOutput(self.output) else { throw OpenLoomError.cameraUnavailable }
                    self.session.addOutput(self.output)
                    // Periodic MOV fragments give recovery more finalized metadata to inspect.
                    // This does not guarantee that an abruptly interrupted take is playable.
                    self.output.movieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 600)
                    self.previewOutput.alwaysDiscardsLateVideoFrames = true
                    self.previewOutput.setSampleBufferDelegate(self.previewFrames, queue: self.previewQueue)
                    if self.session.canAddOutput(self.previewOutput) {
                        self.session.addOutput(self.previewOutput)
                        let formats = self.previewOutput.availableVideoPixelFormatTypes
                        let preferred = [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
                        let pixelFormat = preferred.first(where: { formats.contains($0) }) ?? kCVPixelFormatType_32BGRA
                        self.previewOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat]
                    } else if preview { throw OpenLoomError.cameraUnavailable }
                    try device.lockForConfiguration()
                    let requested = Double(settings.framesPerSecond)
                    let range = device.activeFormat.videoSupportedFrameRateRanges.first { $0.minFrameRate <= requested && requested <= $0.maxFrameRate }
                        ?? device.activeFormat.videoSupportedFrameRateRanges.first
                    let interval: CMTime
                    if let range, requested < range.minFrameRate { interval = range.maxFrameDuration }
                    else if let range, requested > range.maxFrameRate { interval = range.minFrameDuration }
                    else { interval = CMTime(value: 1, timescale: CMTimeScale(settings.framesPerSecond)) }
                    let fps = Int((1 / interval.seconds).rounded())
                    device.activeVideoMinFrameDuration = interval
                    device.activeVideoMaxFrameDuration = interval
                    device.unlockForConfiguration()
                    if let connection = self.output.connection(with: .video) {
                        if connection.isVideoMirroringSupported {
                            connection.automaticallyAdjustsVideoMirroring = false
                            connection.isVideoMirrored = settings.mirrorCamera
                        }
                        let codec: AVVideoCodecType = settings.codec == .hevc ? .hevc : .h264
                        self.output.setOutputSettings([AVVideoCodecKey: codec], for: connection)
                    }
                    let size = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
                    continuation.resume(returning: CameraFormatInfo(width: Int(size.width), height: Int(size.height), framesPerSecond: fps))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func startSession() async {
        await withCheckedContinuation { continuation in
            queue.async {
                if !self.session.isRunning { self.session.startRunning() }
                continuation.resume()
            }
        }
    }

    func stopSession() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                if !self.output.isRecording, self.session.isRunning { self.session.stopRunning() }
                continuation.resume(returning: !self.session.isRunning)
            }
        }
    }

    func startRecording(to url: URL) async throws -> Double {
        try LocalFilePolicy.requireLocalFile(url)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard !self.output.isRecording, self.startWaiter == nil else {
                    continuation.resume(throwing: OpenLoomError.cameraUnavailable); return
                }
                self.startWaiter = continuation
                self.currentURL = url
                self.finished = nil
                if !self.session.isRunning { self.session.startRunning() }
                self.output.startRecording(to: url, recordingDelegate: self)
                self.queue.asyncAfter(deadline: .now() + 15) {
                    guard self.currentURL == url, let waiter = self.startWaiter else { return }
                    self.startWaiter = nil
                    if self.output.isRecording { self.output.stopRecording() }
                    waiter.resume(throwing: OpenLoomError.finishTimedOut)
                }
            }
        }
    }

    func stopRecording() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let result = self.finished { continuation.resume(with: result); return }
                guard self.currentURL != nil, self.finishWaiter == nil else {
                    continuation.resume(throwing: OpenLoomError.noMedia); return
                }
                self.finishWaiter = continuation
                self.output.stopRecording()
                let url = self.currentURL
                self.queue.asyncAfter(deadline: .now() + 30) {
                    guard self.currentURL == url, let waiter = self.finishWaiter else { return }
                    self.finishWaiter = nil
                    waiter.resume(throwing: OpenLoomError.finishTimedOut)
                }
            }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        let time = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        queue.async {
            guard self.currentURL == fileURL, let waiter = self.startWaiter else { return }
            self.startWaiter = nil
            waiter.resume(returning: time)
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: (any Error)?) {
        queue.async {
            guard self.currentURL == outputFileURL else { return }
            let successful = error == nil || (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
            let result: Result<Void, any Error> = successful ? .success(()) : .failure(error ?? OpenLoomError.noMedia)
            self.finished = result
            let wasStarting = self.startWaiter != nil
            if let waiter = self.startWaiter {
                self.startWaiter = nil
                waiter.resume(throwing: error ?? OpenLoomError.noMedia)
            }
            if let waiter = self.finishWaiter { self.finishWaiter = nil; waiter.resume(with: result) }
            else if case .failure(let error) = result { self.onFailure?(error.localizedDescription) }
            else if !wasStarting {
                self.onUnexpectedFinish?(error?.localizedDescription ?? "The camera ended the take unexpectedly.")
            }
        }
    }
}

@preconcurrency import AVFoundation
import CoreImage
import Foundation

extension MediaExporter {
    public func normalizeCamera(input: URL, destination: URL, progress: MediaProgress? = nil) async throws -> Double {
        try LocalFilePolicy.requireLocalFile(input)
        try LocalFilePolicy.requireLocalFile(destination)
        let asset = AVURLAsset(url: input)
        let length = try await duration(of: input)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { throw OpenLoomError.exportUnavailable }
        return try await finishRenderedExport(session: session, destination: destination, length: length, progress: progress)
    }

    public func compositeCamera(screen: URL, camera: URL, cameraOffset: Double,
                                settings: RecordingSettings, destination: URL, progress: MediaProgress? = nil) async throws -> Double {
        for url in [screen, camera, destination] { try LocalFilePolicy.requireLocalFile(url) }
        guard cameraOffset.isFinite, abs(cameraOffset) < 60 else { throw OpenLoomError.invalidSegment }
        let screenAsset = AVURLAsset(url: screen), cameraAsset = AVURLAsset(url: camera)
        let length = try await screenAsset.load(.duration)
        let cameraLength = try await cameraAsset.load(.duration)
        guard let mainSource = try await screenAsset.loadTracks(withMediaType: .video).first,
              let cameraSource = try await cameraAsset.loadTracks(withMediaType: .video).first else { throw OpenLoomError.noMedia }
        let composition = AVMutableComposition()
        guard let main = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let inset = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw OpenLoomError.exportUnavailable }
        try main.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: mainSource, at: .zero)
        let sourceStart = max(0, -cameraOffset), targetStart = max(0, cameraOffset)
        let span = min(cameraLength.seconds - sourceStart, length.seconds - targetStart)
        guard span > 0 else { throw OpenLoomError.invalidSegment }
        try inset.insertTimeRange(CMTimeRange(start: CMTime(seconds: sourceStart, preferredTimescale: 600), duration: CMTime(seconds: span, preferredTimescale: 600)),
                                  of: cameraSource, at: CMTime(seconds: targetStart, preferredTimescale: 600))
        try await insertAudio(from: screenAsset, into: composition, length: length)
        let instruction = VideoRenderInstruction(duration: length, mainTrackID: main.trackID, cameraTrackID: inset.trackID,
                                                mainTransform: try await mainSource.load(.preferredTransform),
                                                cameraTransform: try await cameraSource.load(.preferredTransform), settings: settings)
        let video = try await renderComposition(instruction: instruction, track: mainSource, settings: settings)
        guard let session = AVAssetExportSession(asset: composition, presetName: settings.codec == .hevc ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality) else { throw OpenLoomError.exportUnavailable }
        session.videoComposition = video
        return try await finishRenderedExport(session: session, destination: destination, length: length.seconds, progress: progress)
    }

    public func polish(input: URL, edits: [VisualCue], settings: RecordingSettings, destination: URL, progress: MediaProgress? = nil) async throws -> Double {
        try LocalFilePolicy.requireLocalFile(input)
        try LocalFilePolicy.requireLocalFile(destination)
        let asset = AVURLAsset(url: input)
        let length = try await asset.load(.duration)
        guard !edits.isEmpty, edits.count <= 500 else { throw OpenLoomError.invalidReview }
        for cue in edits { try cue.validate(); guard cue.end <= length.seconds + 0.1 else { throw OpenLoomError.invalidReview } }
        guard let source = try await asset.loadTracks(withMediaType: .video).first else { throw OpenLoomError.noMedia }
        let composition = AVMutableComposition()
        guard let main = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw OpenLoomError.exportUnavailable }
        try main.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: source, at: .zero)
        try await insertAudio(from: asset, into: composition, length: length)
        let instruction = VideoRenderInstruction(duration: length, mainTrackID: main.trackID,
                                                mainTransform: try await source.load(.preferredTransform), settings: settings, edits: edits)
        let video = try await renderComposition(instruction: instruction, track: source, settings: settings)
        guard let session = AVAssetExportSession(asset: composition, presetName: settings.codec == .hevc ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality) else { throw OpenLoomError.exportUnavailable }
        session.videoComposition = video
        return try await finishRenderedExport(session: session, destination: destination, length: length.seconds, progress: progress)
    }

    public func preview(input: URL, time: Double, edits: [VisualCue], settings: RecordingSettings) async throws -> CGImage {
        try LocalFilePolicy.requireLocalFile(input)
        let asset = AVURLAsset(url: input)
        let length = try await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 720)
        let requested = min(max(0, time), max(0, length - 0.05))
        let (frame, _) = try await generator.image(at: CMTime(seconds: requested, preferredTimescale: 600))
        let bounds = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        let renderer = VideoFrameRenderer()
        let image = renderer.render(base: CIImage(cgImage: frame), settings: settings, edits: edits, time: requested, bounds: bounds)
        guard let result = renderer.context.createCGImage(image, from: bounds) else { throw OpenLoomError.exportUnavailable }
        return result
    }

    private func insertAudio(from asset: AVAsset, into composition: AVMutableComposition, length: CMTime) async throws {
        let full = CMTimeRange(start: .zero, duration: length)
        for source in try await asset.loadTracks(withMediaType: .audio) {
            guard let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw OpenLoomError.exportUnavailable }
            let range = CMTimeRangeGetIntersection(try await source.load(.timeRange), otherRange: full)
            if range.duration.seconds > 0 { try target.insertTimeRange(range, of: source, at: range.start) }
        }
    }

    private func renderComposition(instruction: VideoRenderInstruction, track: AVAssetTrack,
                                   settings: RecordingSettings) async throws -> AVMutableVideoComposition {
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let rect = CGRect(origin: .zero, size: natural).applying(transform)
        let video = AVMutableVideoComposition()
        video.customVideoCompositorClass = NativeVideoCompositor.self
        video.renderSize = CGSize(width: abs(rect.width), height: abs(rect.height))
        video.frameDuration = CMTime(value: 1, timescale: CMTimeScale(settings.framesPerSecond))
        video.instructions = [instruction]
        return video
    }

    private func finishRenderedExport(session: AVAssetExportSession, destination: URL, length: Double, progress: MediaProgress? = nil) async throws -> Double {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".export-\(UUID().uuidString).mp4")
        do {
            try Task.checkCancellation()
            try await runExport(session, to: temporary, as: .mp4, estimatedDuration: length, progress: progress)
            let length = try await duration(of: temporary)
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: temporary, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            return length
        } catch { try? FileManager.default.removeItem(at: temporary); throw error }
    }
}

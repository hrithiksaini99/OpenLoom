@preconcurrency import AVFoundation
import Foundation

public actor MediaExporter {
    public init() {}

    public func duration(of url: URL) async throws -> Double {
        try LocalFilePolicy.requireLocalFile(url)
        return try await AsyncDeadline.run(timeout: .seconds(15)) {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard duration.isFinite, duration > 0, !tracks.isEmpty else { throw OpenLoomError.noMedia }
            return duration
        }
    }

    /// Originals are preserved. Only a finished temporary file is promoted to the destination.
    public func assemble(segments: [URL], destination: URL, progress: MediaProgress? = nil) async throws -> Double {
        guard !segments.isEmpty else { throw OpenLoomError.noMedia }
        try LocalFilePolicy.requireLocalFile(destination)
        for segment in segments { try LocalFilePolicy.requireLocalFile(segment) }
        let temporary = temporaryURL(near: destination)
        do {
            if segments.count == 1 {
                let length = try await duration(of: segments[0])
                try Task.checkCancellation()
                if segments[0].pathExtension.lowercased() == "mp4" {
                    try FileManager.default.copyItem(at: segments[0], to: temporary)
                } else {
                    let asset = AVURLAsset(url: segments[0])
                    guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { throw OpenLoomError.exportUnavailable }
                    try await runExport(session, to: temporary, as: .mp4, estimatedDuration: length, progress: progress)
                }
            } else {
                let composition = AVMutableComposition()
                var cursor = CMTime.zero
                var tracksByIndex: [String: AVMutableCompositionTrack] = [:]
                for url in segments {
                    try Task.checkCancellation()
                    let asset = AVURLAsset(url: url)
                    let length = try await asset.load(.duration)
                    guard length.seconds.isFinite, length.seconds > 0 else { throw OpenLoomError.noMedia }
                    let fullRange = CMTimeRange(start: .zero, duration: length)
                    let videoTracks = try await asset.loadTracks(withMediaType: .video)
                    guard !videoTracks.isEmpty else { throw OpenLoomError.noMedia }
                    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                    for (kind, tracks) in [(AVMediaType.video, videoTracks), (.audio, audioTracks)] {
                        for (index, sourceTrack) in tracks.enumerated() {
                            let key = "\(kind.rawValue)-\(index)"
                            let target: AVMutableCompositionTrack
                            if let existing = tracksByIndex[key] { target = existing }
                            else {
                                guard let new = composition.addMutableTrack(withMediaType: kind, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                                    throw OpenLoomError.exportUnavailable
                                }
                                if kind == .video { new.preferredTransform = try await sourceTrack.load(.preferredTransform) }
                                tracksByIndex[key] = new
                                target = new
                            }
                            // Preserve delayed audio starts rather than shifting sound earlier.
                            let sourceRange = try await sourceTrack.load(.timeRange)
                            let range = CMTimeRangeGetIntersection(sourceRange, otherRange: fullRange)
                            if range.duration.seconds > 0 {
                                try target.insertTimeRange(range, of: sourceTrack, at: CMTimeAdd(cursor, range.start))
                            }
                        }
                    }
                    cursor = CMTimeAdd(cursor, length)
                }
                guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
                    throw OpenLoomError.exportUnavailable
                }
                try await runExport(session, to: temporary, as: .mp4, estimatedDuration: cursor.seconds, progress: progress)
            }
            let length = try await duration(of: temporary)
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: temporary, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            await progress?(1)
            return length
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    public func trim(input: URL, start: Double, end: Double, destination: URL, progress: MediaProgress? = nil) async throws {
        try LocalFilePolicy.requireLocalFile(input)
        try LocalFilePolicy.requireLocalFile(destination)
        let length = try await duration(of: input)
        guard start.isFinite, end.isFinite, start >= 0, end <= length + 0.001, end - start >= 0.1 else {
            throw OpenLoomError.invalidTrim
        }
        let asset = AVURLAsset(url: input)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw OpenLoomError.exportUnavailable
        }
        session.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: min(end, length), preferredTimescale: 600))
        let temporary = temporaryURL(near: destination)
        do {
            try Task.checkCancellation()
            try await runExport(session, to: temporary, as: .mp4, estimatedDuration: end - start, progress: progress)
            _ = try await duration(of: temporary)
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: temporary, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    public func extractSpeechAudio(input: URL, destination: URL) async throws {
        try LocalFilePolicy.requireLocalFile(input)
        try LocalFilePolicy.requireLocalFile(destination)
        let asset = AVURLAsset(url: input)
        let sourceTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !sourceTracks.isEmpty else { throw OpenLoomError.noAudio }
        let composition = AVMutableComposition()
        var parameters: [AVMutableAudioMixInputParameters] = []
        for source in sourceTracks {
            guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw OpenLoomError.exportUnavailable
            }
            let range = try await source.load(.timeRange)
            try track.insertTimeRange(range, of: source, at: range.start)
            let parameter = AVMutableAudioMixInputParameters(track: track)
            parameter.setVolume(1 / Float(sourceTracks.count), at: .zero)
            parameters.append(parameter)
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw OpenLoomError.exportUnavailable
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        session.audioMix = mix
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".speech-\(UUID().uuidString).m4a")
        do {
            try Task.checkCancellation()
            try await runExport(session, to: temporary, as: .m4a, estimatedDuration: composition.duration.seconds)
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: temporary, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private func temporaryURL(near destination: URL) -> URL {
        destination.deletingLastPathComponent().appendingPathComponent(".export-\(UUID().uuidString).mp4")
    }
}

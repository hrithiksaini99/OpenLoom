import Foundation

public typealias RecordingProgress = @Sendable (String, Double?) async -> Void

extension MediaExporter {
    /// A paused take is already saved. Compositing is deferred until stop/recovery and never edits sources.
    public func finalize(recording: RecordingManifest, library: RecordingLibrary, includeCamera: Bool = true,
                         progress: RecordingProgress? = nil) async throws -> RecordingManifest {
        var result = recording
        try result.validate()
        let output = library.outputURL(for: result.id)
        try LocalFilePolicy.requireContained(output, in: library.root)
        if FileManager.default.fileExists(atPath: output.path) {
            let length = try await duration(of: output)
            try Task.checkCancellation()
            return try saveReady(result, duration: length, library: library)
        }
        // A crash may occur after the file finished, but before its duration was journaled.
        for index in result.segmentDurations.count..<10_000 {
            let rendered = try library.segmentURL(for: result.id, index: index)
            let raw = result.settings.mode.usesCamera
                ? try library.captureURL(for: result.id, index: index, camera: result.settings.mode == .camera)
                : rendered
            let candidate = FileManager.default.fileExists(atPath: rendered.path) ? rendered : raw
            guard FileManager.default.fileExists(atPath: candidate.path) else { break }
            await progress?("Checking saved source files…", nil)
            let length = try await duration(of: candidate)
            try Task.checkCancellation()
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: candidate.path)
            result.segmentDurations.append(length)
            result.duration = result.segmentDurations.reduce(0, +)
            result.status = .interrupted
            try library.save(result)
        }
        guard !result.segmentDurations.isEmpty else { throw OpenLoomError.noMedia }
        if includeCamera, result.settings.mode == .screenAndCamera {
            for index in result.segmentDurations.indices {
                try Task.checkCancellation()
                let destination = try library.segmentURL(for: result.id, index: index)
                if FileManager.default.fileExists(atPath: destination.path) { continue }
                let screen = try library.captureURL(for: result.id, index: index, camera: false)
                let camera = try library.captureURL(for: result.id, index: index, camera: true)
                let offset = result.cameraSegments.first { $0.index == index }?.offset ?? 0
                let label = "Rendering camera · segment \(index + 1) of \(result.segmentDurations.count)"
                await progress?(label, 0)
                _ = try await compositeCamera(screen: screen, camera: camera, cameraOffset: offset,
                                              settings: result.settings, destination: destination,
                                              progress: { fraction in await progress?(label, fraction) })
            }
        }
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: output.path) {
            result.duration = try await duration(of: output)
        } else {
            await progress?("Assembling saved segments…", 0)
            result.duration = try await assemble(segments: library.completedSegmentURLs(for: result), destination: output,
                                                 progress: { fraction in await progress?("Assembling saved segments…", fraction) })
        }
        try Task.checkCancellation()
        return try saveReady(result, duration: result.duration, library: library)
    }

    private func saveReady(_ recording: RecordingManifest, duration: Double, library: RecordingLibrary) throws -> RecordingManifest {
        try Task.checkCancellation()
        var result = recording
        result.duration = duration
        result.notes = result.notes.map { note in var n = note; n.time = min(n.time, duration); return n }
        result.clicks = result.clicks.filter { $0.time <= duration }
        result.status = .ready
        try library.save(result)
        return result
    }
}

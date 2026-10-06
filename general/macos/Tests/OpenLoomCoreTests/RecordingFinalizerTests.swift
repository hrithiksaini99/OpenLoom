@preconcurrency import AVFoundation
import Foundation
import OpenLoomCore
import Testing

@Suite(.serialized) struct RecordingFinalizerTests {
    @Test func pauseCheckpointCanRenderCameraLaterWithoutChangingSources() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = RecordingLibrary(root: root), exporter = MediaExporter()
        var settings = RecordingSettings(); settings.mode = .screenAndCamera
        var recording = try library.create(title: "Paused take", source: "Synthetic", settings: settings)
        let screen = try library.captureURL(for: recording.id, index: 0, camera: false)
        let camera = try library.captureURL(for: recording.id, index: 0, camera: true)
        try await SyntheticMedia.write(to: screen, audioTracks: 1)
        try await SyntheticMedia.write(to: camera, blue: true, audioTracks: 0)
        let beforeScreen = try Data(contentsOf: screen), beforeCamera = try Data(contentsOf: camera)
        recording.segmentDurations = [1]; recording.duration = 1
        recording.cameraSegments = [.init(index: 0, offset: 0.2)]
        try library.save(recording)
        #expect(!FileManager.default.fileExists(atPath: try library.segmentURL(for: recording.id, index: 0).path))
        let scanned = try library.scan().recordings[0]
        #expect(scanned.cameraSegments == recording.cameraSegments)
        let finished = try await exporter.finalize(recording: scanned, library: library)
        #expect(finished.status == .ready)
        #expect(try Data(contentsOf: screen) == beforeScreen)
        #expect(try Data(contentsOf: camera) == beforeCamera)
        #expect(abs(finished.duration - 1) < 0.1)
    }

    @Test func recoveryFindsFilesWrittenBeforeMetadataCheckpoint() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = RecordingLibrary(root: root), exporter = MediaExporter()
        let recording = try library.create(title: "Interrupted metadata", source: "Synthetic", settings: RecordingSettings())
        let source = try library.segmentURL(for: recording.id, index: 0)
        try await SyntheticMedia.write(to: source)
        let bytes = try Data(contentsOf: source)
        #expect(recording.segmentDurations.isEmpty)
        #expect(library.hasCaptureFiles(for: recording))
        let recovered = try await exporter.finalize(recording: recording, library: library)
        #expect(recovered.segmentDurations.count == 1)
        #expect(recovered.status == .ready)
        #expect(try Data(contentsOf: source) == bytes)
    }

    @Test func cameraOnlyRawMovieIsRecoveredIntoAnActualMP4() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = RecordingLibrary(root: root), exporter = MediaExporter()
        var settings = RecordingSettings(); settings.mode = .camera
        let recording = try library.create(title: "Raw camera", source: "Synthetic", settings: settings)
        let input = library.folder(for: recording.id).appendingPathComponent("test-input.mp4")
        try await SyntheticMedia.write(to: input)
        let raw = try library.captureURL(for: recording.id, index: 0, camera: true)
        let session = try #require(AVAssetExportSession(asset: AVURLAsset(url: input), presetName: AVAssetExportPresetPassthrough))
        try await session.export(to: raw, as: .mov)
        let original = try Data(contentsOf: raw)
        let finished = try await exporter.finalize(recording: recording, library: library)
        let output = library.outputURL(for: recording.id)
        #expect(finished.status == .ready)
        #expect(try await AVURLAsset(url: output).loadTracks(withMediaType: .audio).count == 1)
        #expect(try Data(contentsOf: raw) == original)
        #expect(try Data(contentsOf: output).prefix(64) != original.prefix(64))
    }

    @Test func missingCameraPreservesScreenAndAllowsExplicitScreenOnlyRecovery() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = RecordingLibrary(root: root), exporter = MediaExporter()
        var settings = RecordingSettings(); settings.mode = .screenAndCamera
        let recording = try library.create(title: "Camera interrupted", source: "Synthetic", settings: settings)
        let screen = try library.captureURL(for: recording.id, index: 0, camera: false)
        try await SyntheticMedia.write(to: screen)
        let original = try Data(contentsOf: screen)
        await #expect(throws: (any Error).self) { try await exporter.finalize(recording: recording, library: library) }
        #expect(try Data(contentsOf: screen) == original)
        #expect(!FileManager.default.fileExists(atPath: library.outputURL(for: recording.id).path))
        let checkpoint = try library.scan().recordings[0]
        #expect(checkpoint.segmentDurations.count == 1)
        let recovered = try await exporter.finalize(recording: checkpoint, library: library, includeCamera: false)
        #expect(recovered.status == .ready)
        #expect(try Data(contentsOf: screen) == original)
    }

    @Test func cancellationBeforeCommitLeavesSourceAndManifestRecoverable() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = RecordingLibrary(root: root), exporter = MediaExporter(), hold = NonCooperativeOperation()
        let recording = try library.create(title: "Cancelled recovery", source: "Synthetic", settings: RecordingSettings())
        let segment = try library.segmentURL(for: recording.id, index: 0)
        try await SyntheticMedia.write(to: segment)
        let original = try Data(contentsOf: segment)
        let task = Task {
            try await exporter.finalize(recording: recording, library: library, progress: { _, _ in _ = await hold.wait() })
        }
        try await Task.sleep(for: .milliseconds(10))
        task.cancel(); await hold.finish(1)
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try Data(contentsOf: segment) == original)
        #expect(!FileManager.default.fileExists(atPath: library.outputURL(for: recording.id).path))
        #expect(try library.scan().recordings[0].status != .ready)
    }

    @Test func finishedOutputSurvivesInterruptedMetadataWithoutSegmentFiles() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = RecordingLibrary(root: root), exporter = MediaExporter()
        let recording = try library.create(title: "Output already written", source: "Synthetic", settings: RecordingSettings())
        let output = library.outputURL(for: recording.id)
        try await SyntheticMedia.write(to: output)
        let original = try Data(contentsOf: output)
        let recovered = try await exporter.finalize(recording: recording, library: library)
        #expect(recovered.status == .ready)
        #expect(try Data(contentsOf: output) == original)
    }

    @Test func lateExportCompletionAfterCancellationCannotPromoteAFile() async throws {
        let root = temporaryRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mp4"), output = root.appendingPathComponent("rendered.mp4")
        try await SyntheticMedia.write(to: source)
        let original = try Data(contentsOf: source)
        let exporter = MediaExporter(), exportFinished = NonCooperativeOperation(), hold = NonCooperativeOperation(), workerExited = NonCooperativeOperation()
        let task = Task {
            try await AsyncDeadline.run(timeout: .seconds(10)) {
                do {
                    _ = try await exporter.normalizeCamera(input: source, destination: output, progress: { fraction in
                        if fraction == 1 { await exportFinished.finish(1); _ = await hold.wait() }
                    })
                    await workerExited.finish(1)
                } catch { await workerExited.finish(1); throw error }
            }
        }
        _ = try await AsyncDeadline.run(timeout: .seconds(5)) { await exportFinished.wait() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: output.path))
        await hold.finish(1)
        _ = try await AsyncDeadline.run(timeout: .seconds(5)) { await workerExited.wait() }
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(try Data(contentsOf: source) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".export-") })
    }

    private func temporaryRoot() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
}

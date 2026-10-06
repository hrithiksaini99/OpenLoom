@preconcurrency import AVFoundation
import Foundation
import OpenLoomCore
import Testing

@Suite(.serialized)
struct MediaExporterTests {
    @Test func pauseSegmentsAssembleInOrderAndPreserveAudio() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let red = root.appendingPathComponent("red.mp4")
        let blue = root.appendingPathComponent("blue.mp4")
        let joined = root.appendingPathComponent("joined.mp4")
        try await SyntheticMedia.write(to: red, audioTracks: 2)
        try await SyntheticMedia.write(to: blue, blue: true, audioTracks: 2)
        let originalRed = try Data(contentsOf: red)
        let originalBlue = try Data(contentsOf: blue)
        let exporter = MediaExporter()
        let length = try await exporter.assemble(segments: [red, blue], destination: joined)
        #expect(abs(length - 2) < 0.15)
        let asset = AVURLAsset(url: joined)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        #expect(audio.count == 2)
        for track in audio { #expect(try await track.load(.timeRange).duration.seconds > 1.8) }
        let first = try await color(at: 0.25, url: joined)
        let second = try await color(at: 1.25, url: joined)
        #expect(first.red > first.blue * 2)
        #expect(second.blue > second.red * 2)
        #expect(try Data(contentsOf: red) == originalRed)
        #expect(try Data(contentsOf: blue) == originalBlue)
        let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(!remainingFiles.contains { $0.hasPrefix(".export-") })
    }

    @Test func trimProducesRequestedDurationAndKeepsOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.mp4")
        let trimmed = root.appendingPathComponent("trimmed.mp4")
        let first = root.appendingPathComponent("first.mp4")
        let second = root.appendingPathComponent("second.mp4")
        try await SyntheticMedia.write(to: first)
        try await SyntheticMedia.write(to: second, blue: true)
        let exporter = MediaExporter()
        _ = try await exporter.assemble(segments: [first, second], destination: original)
        let before = try Data(contentsOf: original)
        try await exporter.trim(input: original, start: 0.4, end: 1.6, destination: trimmed)
        let duration = try await exporter.duration(of: trimmed)
        #expect(abs(duration - 1.2) < 0.15)
        #expect(try Data(contentsOf: original) == before)
        #expect(try await AVURLAsset(url: trimmed).loadTracks(withMediaType: .audio).count == 1)
        let trimmedStart = try await color(at: 0.1, url: trimmed)
        let trimmedEnd = try await color(at: 1.0, url: trimmed)
        #expect(trimmedStart.red > trimmedStart.blue * 2)
        #expect(trimmedEnd.blue > trimmedEnd.red * 2)
        let attributes = try FileManager.default.attributesOfItem(atPath: trimmed.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func failedExportsNeverReplaceExistingMedia() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.mp4")
        let destination = root.appendingPathComponent("existing.mp4")
        try await SyntheticMedia.write(to: original, audioTracks: 0)
        let sentinel = Data("do not replace".utf8)
        try sentinel.write(to: destination)
        let exporter = MediaExporter()
        await #expect(throws: (any Error).self) { try await exporter.assemble(segments: [original], destination: destination) }
        #expect(try Data(contentsOf: destination) == sentinel)
        await #expect(throws: OpenLoomError.self) { try await exporter.trim(input: original, start: -1, end: 0.5, destination: root.appendingPathComponent("invalid.mp4")) }
        await #expect(throws: OpenLoomError.self) { try await exporter.assemble(segments: [], destination: root.appendingPathComponent("empty.mp4")) }
    }

    @Test func interruptedSessionCanRebuildFromFinalizedSegments() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = RecordingLibrary(root: root)
        var manifest = try library.create(title: "Recovered demo", source: "Display", settings: RecordingSettings())
        let segment = try library.segmentURL(for: manifest.id, index: 0)
        try await SyntheticMedia.write(to: segment)
        manifest.segmentDurations = [1]
        manifest.status = .interrupted
        try library.save(manifest)
        let scanned = try library.scan().recordings[0]
        let exporter = MediaExporter()
        manifest.duration = try await exporter.assemble(segments: library.completedSegmentURLs(for: scanned), destination: library.outputURL(for: manifest.id))
        manifest.status = .ready
        try library.save(manifest)
        #expect(try library.scan().recordings[0].status == .ready)
        #expect(FileManager.default.fileExists(atPath: segment.path))
    }

    private func color(at seconds: Double, url: URL) async throws -> (red: Int, blue: Int) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { data in
            let context = CGContext(data: data.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return (Int(bytes[0]), Int(bytes[2]))
    }
}

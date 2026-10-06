@preconcurrency import AVFoundation
import Foundation
import OpenLoomCore
import Testing

@Suite(.serialized)
struct VideoEditingTests {
    @Test func generatedDemoIsPlayableAndContainsNoDeviceAudio() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("demo.mp4")
        try await LocalDemoGenerator().write(to: url)
        let exporter = MediaExporter()
        #expect(abs(try await exporter.duration(of: url) - 6) < 0.1)
        let asset = AVURLAsset(url: url)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 960, height: 540))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
    @Test func cameraMovieNormalizesToMP4WithoutLosingAudioOrOriginal() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let camera = root.appendingPathComponent("camera.mov"), output = root.appendingPathComponent("video.mp4")
        try await SyntheticMedia.write(to: camera, blue: true, audioTracks: 1, fileType: .mov)
        let original = try Data(contentsOf: camera)
        let exporter = MediaExporter()
        #expect(abs(try await exporter.normalizeCamera(input: camera, destination: output) - 1) < 0.1)
        #expect(try await AVURLAsset(url: output).loadTracks(withMediaType: .audio).count == 1)
        #expect(try Data(contentsOf: camera) == original)
        let pixel = try await pixel(url: output, time: 0.5, x: 0.5, y: 0.5)
        #expect(pixel.b > pixel.r * 2)
    }

    @Test func cameraBubbleHasCircularMaskAlignedTimingAndScreenAudio() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let screen = root.appendingPathComponent("screen.mp4"), camera = root.appendingPathComponent("camera.mov")
        let output = root.appendingPathComponent("composite.mp4")
        try await SyntheticMedia.write(to: screen, audioTracks: 1)
        try await SyntheticMedia.write(to: camera, blue: true, audioTracks: 0, fileType: .mov)
        var settings = RecordingSettings(); settings.mode = .screenAndCamera; settings.cameraPosition = .topLeft
        let exporter = MediaExporter()
        let length = try await exporter.compositeCamera(screen: screen, camera: camera, cameraOffset: 0.3, settings: settings, destination: output)
        #expect(abs(length - 1) < 0.15)
        let before = try await pixel(url: output, time: 0.1, x: 28.0 / 160, y: 28.0 / 90)
        let inset = try await pixel(url: output, time: 0.6, x: 28.0 / 160, y: 28.0 / 90)
        let corner = try await pixel(url: output, time: 0.6, x: 10.0 / 160, y: 10.0 / 90)
        #expect(before.r > before.b * 2)
        #expect(inset.b > inset.r * 2)
        #expect(corner.r > corner.b * 2)
        #expect(try await AVURLAsset(url: output).loadTracks(withMediaType: .audio).count >= 1)
        #expect(FileManager.default.fileExists(atPath: camera.path))
        #expect(FileManager.default.fileExists(atPath: screen.path))
    }

    @Test func timedDrawingAndEditorPreviewMatchExportAndPreserveOriginal() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.mp4"), output = root.appendingPathComponent("polished.mp4")
        try await SyntheticMedia.write(to: original)
        let before = try Data(contentsOf: original)
        let cue = VisualCue(start: 0.2, end: 0.7, tool: .arrow, points: [.init(x: 0.2, y: 0.5), .init(x: 0.8, y: 0.5)], color: .green)
        let exporter = MediaExporter()
        _ = try await exporter.polish(input: original, edits: [cue], settings: RecordingSettings(), destination: output)
        let inactive = try await pixel(url: output, time: 0.1, x: 0.5, y: 0.5)
        let active = try await pixel(url: output, time: 0.4, x: 0.5, y: 0.5)
        #expect(inactive.r > inactive.g * 2)
        // H.264 chroma subsampling blends this three-pixel stroke with its red background.
        #expect(active.g > active.r + 50)
        let preview = try await exporter.preview(input: original, time: 0.4, edits: [cue], settings: RecordingSettings())
        let previewPixel = try sample(preview, x: 0.5, y: 0.5)
        #expect(previewPixel.g > previewPixel.r * 2)
        #expect(try Data(contentsOf: original) == before)
        #expect(try await AVURLAsset(url: output).loadTracks(withMediaType: .audio).count >= 1)
    }

    @Test func cameraStartingBeforeScreenTrimsItsLeadIn() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let screen = root.appendingPathComponent("screen.mp4")
        let first = root.appendingPathComponent("camera-first.mp4"), second = root.appendingPathComponent("camera-second.mp4")
        let camera = root.appendingPathComponent("camera.mp4"), output = root.appendingPathComponent("aligned.mp4")
        try await SyntheticMedia.write(to: screen, audioTracks: 0)
        try await SyntheticMedia.write(to: first, blue: true, audioTracks: 0)
        try await SyntheticMedia.write(to: second, audioTracks: 0)
        let exporter = MediaExporter()
        _ = try await exporter.assemble(segments: [first, second], destination: camera)
        var settings = RecordingSettings(); settings.cameraPosition = .topLeft
        _ = try await exporter.compositeCamera(screen: screen, camera: camera, cameraOffset: -0.5, settings: settings, destination: output)
        let early = try await pixel(url: output, time: 0.2, x: 28.0 / 160, y: 28.0 / 90)
        let late = try await pixel(url: output, time: 0.7, x: 28.0 / 160, y: 28.0 / 90)
        #expect(early.b > early.r * 2)
        #expect(late.r > late.b * 2)
    }

    @Test func zoomChangesFramingOnlyInsideItsTimeRange() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("patch.mp4"), output = root.appendingPathComponent("zoom.mp4")
        try await SyntheticMedia.write(to: original, audioTracks: 0, bluePatch: true)
        let cue = VisualCue(start: 0.1, end: 0.8, tool: .zoom, points: [.init(x: 0.2, y: 0.2)], zoom: 2.2)
        let exporter = MediaExporter()
        _ = try await exporter.polish(input: original, edits: [cue], settings: RecordingSettings(), destination: output)
        let normal = try await pixel(url: output, time: 0.0, x: 0.5, y: 0.5)
        let zoomed = try await pixel(url: output, time: 0.45, x: 0.5, y: 0.5)
        let after = try await pixel(url: output, time: 0.9, x: 0.5, y: 0.5)
        #expect(normal.r > normal.b * 2)
        #expect(zoomed.b > zoomed.r * 2)
        #expect(after.r > after.b * 2)
    }

    @Test func speechAudioMixesTracksLocallyAndRejectsSilentVideo() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("two-audio.mp4"), audio = root.appendingPathComponent("speech.m4a")
        try await SyntheticMedia.write(to: original, audioTracks: 2)
        let exporter = MediaExporter()
        try await exporter.extractSpeechAudio(input: original, destination: audio)
        let file = try AVAudioFile(forReading: audio)
        #expect(file.length > 40_000)
        let length = try await AVURLAsset(url: audio).load(.duration).seconds
        #expect(abs(length - 1) < 0.2)
        let silent = root.appendingPathComponent("silent.mp4")
        try await SyntheticMedia.write(to: silent, audioTracks: 0)
        await #expect(throws: OpenLoomError.self) { try await exporter.extractSpeechAudio(input: silent, destination: root.appendingPathComponent("none.m4a")) }
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func pixel(url: URL, time: Double, x: Double, y: Double) async throws -> (r: Int, g: Int, b: Int) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
        return try sample(image, x: x, y: y)
    }
    private func sample(_ image: CGImage, x: Double, y: Double) throws -> (r: Int, g: Int, b: Int) {
        let crop = try #require(image.cropping(to: CGRect(x: Int(x * Double(image.width)), y: Int(y * Double(image.height)), width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { data in
            let context = CGContext(data: data.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }
}

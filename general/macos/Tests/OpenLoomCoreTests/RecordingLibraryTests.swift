import Foundation
import OpenLoomCore
import Testing

struct RecordingLibraryTests {
    @Test func readingLatestCheckpointPreservesTakesAndRejectsAnotherSessionsMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = RecordingLibrary(root: root)
        var first = try library.create(title: "Checkpoint", source: "Generated", settings: RecordingSettings())
        let second = try library.create(title: "Different session", source: "Generated", settings: RecordingSettings())
        first.segmentDurations = [1, 2]; first.duration = 3
        first.status = .interrupted
        try library.save(first)
        #expect(try library.load(first.id).segmentDurations == [1, 2])
        let bytes = try Data(contentsOf: library.folder(for: first.id).appendingPathComponent("manifest.json"))
        try bytes.write(to: library.folder(for: second.id).appendingPathComponent("manifest.json"), options: .atomic)
        #expect(throws: OpenLoomError.self) { try library.load(second.id) }
        #expect(try library.scan().recordings.count == 1)
    }

    @Test func libraryRoundTripAndPrivateMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = RecordingLibrary(root: root)
        let recording = try library.create(title: "  A private demo  ", source: "Window", settings: RecordingSettings())
        let snapshot = try library.scan()
        #expect(snapshot.recordings.count == 1)
        #expect(snapshot.recordings[0].id == recording.id)
        #expect(snapshot.recordings[0].title == "A private demo")
        #expect(snapshot.recordings[0].settings == RecordingSettings())
        let path = library.folder(for: recording.id).appendingPathComponent("manifest.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try library.rename(recording, to: "Updated title")
        #expect(try library.scan().recordings[0].title == "Updated title")
    }

    @Test func titlesNeverDeterminePaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = RecordingLibrary(root: root)
        let recording = try library.create(title: "../../outside", source: "Window", settings: RecordingSettings())
        #expect(library.folder(for: recording.id).lastPathComponent == recording.id.uuidString)
        #expect(throws: OpenLoomError.self) { try library.rename(recording, to: " \n ") }
        #expect(throws: OpenLoomError.self) { try library.segmentURL(for: recording.id, index: -1) }
    }

    @Test func symlinkCannotEscapePrivateLibrary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let library = RecordingLibrary(root: root)
        let recording = try library.create(title: "Demo", source: "Window", settings: RecordingSettings())
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let segments = library.folder(for: recording.id).appendingPathComponent("segments")
        try FileManager.default.removeItem(at: segments)
        try FileManager.default.createSymbolicLink(at: segments, withDestinationURL: outside)
        #expect(throws: OpenLoomError.self) { try library.segmentURL(for: recording.id, index: 0) }
        #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("segment-0000.mp4").path))
    }

    @Test func corruptAndMissingOutputDoNotHideHealthySessions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = RecordingLibrary(root: root)
        _ = try library.create(title: "Healthy", source: "Display", settings: RecordingSettings())
        var missing = try library.create(title: "Missing", source: "Display", settings: RecordingSettings())
        missing.status = .ready
        try library.save(missing)
        let broken = try library.create(title: "Broken", source: "Display", settings: RecordingSettings())
        try Data("bad JSON".utf8).write(to: library.folder(for: broken.id).appendingPathComponent("manifest.json"))
        let snapshot = try library.scan()
        #expect(snapshot.recordings.count == 1)
        #expect(snapshot.recordings[0].title == "Healthy")
        #expect(snapshot.warnings.count == 2)
    }

    @Test func unsupportedMetadataAndRemoteURLsAreRejected() throws {
        #expect(throws: OpenLoomError.self) { try LocalFilePolicy.requireLocalFile(URL(string: "https://example.com/video.mp4")!) }
        var recording = RecordingManifest(title: "Demo", source: "Display", settings: RecordingSettings())
        recording.segmentDurations = [.infinity]
        #expect(throws: OpenLoomError.self) { try recording.validate() }
        recording.segmentDurations = []
        var settings = RecordingSettings()
        settings.framesPerSecond = 1000
        #expect(throws: OpenLoomError.self) { try settings.validate() }
    }

    @Test func sizingPreservesAspectAndNeverUpscales() throws {
        let retina = try CaptureDimensions.fit(width: 5120, height: 2880, preset: .hd1080)
        #expect(retina.width == 1920 && retina.height == 1080)
        let window = try CaptureDimensions.fit(width: 601, height: 401, preset: .uhd4K)
        #expect(window.width == 600 && window.height == 400)
        let portrait = try CaptureDimensions.fit(width: 1800, height: 2880, preset: .hd1080)
        #expect(portrait.height == 1080 && portrait.width <= 676)
        #expect(throws: OpenLoomError.self) { try CaptureDimensions.fit(width: .nan, height: 900, preset: .hd1080) }
        #expect(throws: OpenLoomError.self) { try CaptureDimensions.fit(width: 1, height: 900, preset: .hd1080) }
    }
}

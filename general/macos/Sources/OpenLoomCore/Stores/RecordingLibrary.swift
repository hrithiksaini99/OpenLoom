import Foundation

/// Immutable path policy; callers serialize mutations for each recording.
public struct RecordingLibrary: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenLoom", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    public func prepare() throws {
        guard root.isFileURL else { throw OpenLoomError.remoteURL }
        try makeDirectory(root)
        try LocalFilePolicy.requireLocalFile(root)
    }

    public func folder(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    public func outputURL(for id: UUID) -> URL { folder(for: id).appendingPathComponent("recording.mp4") }

    public func segmentURL(for id: UUID, index: Int) throws -> URL {
        guard (0..<10_000).contains(index) else { throw OpenLoomError.invalidSegment }
        let url = folder(for: id).appendingPathComponent("segments/segment-\(String(format: "%04d", index)).mp4")
        try LocalFilePolicy.requireContained(url, in: root)
        return url
    }

    public func captureURL(for id: UUID, index: Int, camera: Bool) throws -> URL {
        guard (0..<10_000).contains(index) else { throw OpenLoomError.invalidSegment }
        let name = camera ? "camera" : "screen"
        let ext = camera ? "mov" : "mp4"
        let url = folder(for: id).appendingPathComponent("segments/\(name)-\(String(format: "%04d", index)).\(ext)")
        try LocalFilePolicy.requireContained(url, in: root)
        return url
    }

    public func create(title: String, source: String, settings: RecordingSettings) throws -> RecordingManifest {
        try prepare()
        try settings.validate()
        let cleanTitle = try Self.validTitle(title)
        let manifest = RecordingManifest(title: cleanTitle, source: String(source.prefix(400)), settings: settings)
        let directory = folder(for: manifest.id)
        try makeDirectory(directory)
        try makeDirectory(directory.appendingPathComponent("segments", isDirectory: true))
        try makeDirectory(directory.appendingPathComponent("exports", isDirectory: true))
        try save(manifest)
        return manifest
    }

    public func save(_ manifest: RecordingManifest) throws {
        try manifest.validate()
        let url = folder(for: manifest.id).appendingPathComponent("manifest.json")
        try LocalFilePolicy.requireContained(url, in: root)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func load(_ id: UUID) throws -> RecordingManifest {
        let url = folder(for: id).appendingPathComponent("manifest.json")
        try LocalFilePolicy.requireContained(url, in: root)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(RecordingManifest.self, from: Data(contentsOf: url))
        try manifest.validate()
        guard manifest.id == id else { throw OpenLoomError.invalidManifest }
        if manifest.status == .ready {
            let output = outputURL(for: id)
            try LocalFilePolicy.requireContained(output, in: root)
            guard FileManager.default.fileExists(atPath: output.path) else { throw OpenLoomError.noMedia }
        }
        return manifest
    }

    public func scan() throws -> LibrarySnapshot {
        try prepare()
        var recordings: [RecordingManifest] = []
        var warnings: [String] = []
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        for folder in folders {
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            do {
                recordings.append(try load(id))
            } catch {
                warnings.append("Could not read a local recording (\(id.uuidString.prefix(8))): \(error.localizedDescription)")
            }
        }
        return LibrarySnapshot(recordings: recordings.sorted { $0.createdAt > $1.createdAt }, warnings: warnings)
    }

    public func rename(_ manifest: RecordingManifest, to title: String) throws {
        var updated = manifest
        updated.title = try Self.validTitle(title)
        try save(updated)
    }

    public func completedSegmentURLs(for manifest: RecordingManifest) throws -> [URL] {
        try manifest.validate()
        return try manifest.segmentDurations.indices.map { index in
            let url = try segmentURL(for: manifest.id, index: index)
            if FileManager.default.fileExists(atPath: url.path) { return url }
            guard manifest.settings.mode.usesCamera else { throw OpenLoomError.invalidSegment }
            let raw = try captureURL(for: manifest.id, index: index, camera: manifest.settings.mode == .camera)
            guard FileManager.default.fileExists(atPath: raw.path) else { throw OpenLoomError.invalidSegment }
            return raw
        }
    }

    public func hasCaptureFiles(for recording: RecordingManifest) -> Bool {
        let candidates = [try? segmentURL(for: recording.id, index: 0),
                          try? captureURL(for: recording.id, index: 0, camera: false),
                          try? captureURL(for: recording.id, index: 0, camera: true)]
        return candidates.compactMap { $0 }.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func newExportURL(for id: UUID, name: String = "trim", extension ext: String = "mp4") throws -> URL {
        guard ["trim", "polished", "captions", "review", "speech"].contains(name),
              ["mp4", "srt", "vtt", "md", "m4a"].contains(ext) else { throw OpenLoomError.unsafePath }
        let directory = folder(for: id).appendingPathComponent("exports", isDirectory: true)
        try LocalFilePolicy.requireContained(directory, in: root)
        try makeDirectory(directory)
        return directory.appendingPathComponent("\(name)-\(UUID().uuidString).\(ext)")
    }

    public func exportCaptions(_ recording: RecordingManifest) throws -> [URL] {
        try recording.validate()
        guard let transcript = recording.transcript else { throw OpenLoomError.invalidReview }
        let srt = try newExportURL(for: recording.id, name: "captions", extension: "srt")
        let vtt = try newExportURL(for: recording.id, name: "captions", extension: "vtt")
        try writePrivateText(transcript.srt, to: srt)
        try writePrivateText(transcript.vtt, to: vtt)
        return [srt, vtt]
    }

    public func exportReview(_ recording: RecordingManifest) throws -> URL {
        try recording.validate()
        func clean(_ value: String) -> String {
            value.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        }
        func time(_ seconds: Double) -> String { String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
        var text = "# \(clean(recording.title))\n\nLocal recording · \(time(recording.duration))\n\n"
        for kind in NoteKind.allCases {
            let notes = recording.notes.filter { $0.kind == kind }.sorted { $0.time < $1.time }
            if !notes.isEmpty {
                text += "## \(kind == .chapter ? "Chapters" : "Notes")\n\n"
                text += notes.map { "- **\(time($0.time))** \(clean($0.text))" }.joined(separator: "\n") + "\n\n"
            }
        }
        if let transcript = recording.transcript {
            text += "## Transcript\n\n" + transcript.cues.map { "**\(time($0.start))** \(clean($0.text))" }.joined(separator: "\n\n") + "\n"
        }
        let url = try newExportURL(for: recording.id, name: "review", extension: "md")
        try writePrivateText(text, to: url)
        return url
    }

    private func writePrivateText(_ text: String, to url: URL) throws {
        try LocalFilePolicy.requireContained(url, in: root)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw OpenLoomError.unsafePath }
        try Data(text.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func checkFreeSpace() throws {
        try prepare()
        let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage, available < 500_000_000 {
            throw OpenLoomError.lowDiskSpace
        }
    }

    private func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    private static func validTitle(_ input: String) throws -> String {
        let title = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 200 else { throw OpenLoomError.invalidTitle }
        return title
    }
}

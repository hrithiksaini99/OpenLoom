import Foundation

public enum RecordingStatus: String, Codable, Sendable {
    case recording, interrupted, ready
}

/// Persisted before processing so a finalized raw camera take can be rebuilt after interruption.
public struct CameraSegmentCheckpoint: Codable, Equatable, Sendable {
    public let index: Int
    public let offset: Double
    public init(index: Int, offset: Double) { self.index = index; self.offset = offset }
}

public struct RecordingManifest: Codable, Identifiable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public let source: String
    public let settings: RecordingSettings
    public var status: RecordingStatus
    public var segmentDurations: [Double]
    public var duration: Double
    public var transcript: LocalTranscript?
    public var notes: [TimedNote]
    public var visualEdits: [VisualCue]
    public var clicks: [CursorClick]
    public var cameraSegments: [CameraSegmentCheckpoint]

    public init(id: UUID = UUID(), title: String, source: String, settings: RecordingSettings) {
        self.schemaVersion = 1
        self.id = id
        self.title = title
        self.createdAt = Date()
        self.source = source
        self.settings = settings
        self.status = .recording
        self.segmentDurations = []
        self.duration = 0
        self.transcript = nil
        self.notes = []
        self.visualEdits = []
        self.clicks = []
        self.cameraSegments = []
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, title, createdAt, source, settings, status, segmentDurations, duration
        case transcript, notes, visualEdits, clicks
        case cameraSegments
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        source = try c.decode(String.self, forKey: .source)
        settings = try c.decode(RecordingSettings.self, forKey: .settings)
        status = try c.decode(RecordingStatus.self, forKey: .status)
        segmentDurations = try c.decode([Double].self, forKey: .segmentDurations)
        duration = try c.decode(Double.self, forKey: .duration)
        transcript = try c.decodeIfPresent(LocalTranscript.self, forKey: .transcript)
        notes = try c.decodeIfPresent([TimedNote].self, forKey: .notes) ?? []
        visualEdits = try c.decodeIfPresent([VisualCue].self, forKey: .visualEdits) ?? []
        clicks = try c.decodeIfPresent([CursorClick].self, forKey: .clicks) ?? []
        cameraSegments = try c.decodeIfPresent([CameraSegmentCheckpoint].self, forKey: .cameraSegments) ?? []
    }

    public func validate() throws {
        guard schemaVersion == 1, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 200, source.count <= 400, duration.isFinite, duration >= 0,
              segmentDurations.count < 10_000,
              segmentDurations.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw OpenLoomError.invalidManifest
        }
        try settings.validate()
        guard cameraSegments.count < 10_000, Set(cameraSegments.map(\.index)).count == cameraSegments.count,
              cameraSegments.allSatisfy({ (0..<10_000).contains($0.index) && $0.offset.isFinite && abs($0.offset) < 60 }) else {
            throw OpenLoomError.invalidManifest
        }
        guard notes.count <= 10_000, visualEdits.count <= 500, clicks.count <= 100_000 else { throw OpenLoomError.invalidReview }
        try transcript?.validate()
        for note in notes { try note.validate() }
        for cue in visualEdits { try cue.validate() }
        for click in clicks { try click.validate() }
        if status == .ready {
            guard notes.allSatisfy({ $0.time <= duration + 0.1 }),
                  visualEdits.allSatisfy({ $0.end <= duration + 0.1 }),
                  clicks.allSatisfy({ $0.time <= duration + 0.1 }),
                  transcript?.cues.allSatisfy({ $0.end <= duration + 0.1 }) ?? true else {
                throw OpenLoomError.invalidReview
            }
        }
    }
}

public struct LibrarySnapshot: Sendable {
    public let recordings: [RecordingManifest]
    public let warnings: [String]
}

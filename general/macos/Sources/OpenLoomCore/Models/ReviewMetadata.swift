import Foundation

public enum NoteKind: String, Codable, CaseIterable, Sendable {
    case chapter, note
    public var label: String { rawValue.capitalized }
}

public struct TimedNote: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var time: Double
    public var text: String
    public var kind: NoteKind
    public init(id: UUID = UUID(), time: Double, text: String, kind: NoteKind) {
        self.id = id; self.time = time; self.text = text; self.kind = kind
    }
    public func validate() throws {
        guard time.isFinite, time >= 0, time <= 86_400,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 2_000 else {
            throw OpenLoomError.invalidReview
        }
    }
}

public struct TranscriptCue: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var start: Double
    public var end: Double
    public var text: String
    public init(id: UUID = UUID(), start: Double, end: Double, text: String) {
        self.id = id; self.start = start; self.end = end; self.text = text
    }
    public func validate() throws {
        guard start.isFinite, end.isFinite, start >= 0, end > start, end <= 86_400,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 10_000 else {
            throw OpenLoomError.invalidReview
        }
    }
}

public struct TimedSpeechRun: Sendable {
    public var text: String
    public let start: Double
    public let end: Double
    public init(text: String, start: Double, end: Double) { self.text = text; self.start = start; self.end = end }
}

public struct LocalTranscript: Codable, Equatable, Sendable {
    public let localeIdentifier: String
    public let createdAt: Date
    public let engine: String
    public var cues: [TranscriptCue]
    public init(localeIdentifier: String, cues: [TranscriptCue], engine: String = "Apple SpeechTranscriber · on device") {
        self.localeIdentifier = localeIdentifier; self.cues = cues
        createdAt = .now; self.engine = engine
    }
    public func validate() throws {
        guard localeIdentifier.count <= 100, engine.count <= 200, cues.count <= 100_000 else {
            throw OpenLoomError.invalidReview
        }
        for cue in cues { try cue.validate() }
        guard zip(cues, cues.dropFirst()).allSatisfy({ $0.start <= $1.start }) else { throw OpenLoomError.invalidReview }
    }
    public var plainText: String { cues.map(\.text).joined(separator: " ") }
    public func caption(at time: Double) -> String? {
        cues.first { $0.start <= time && time < $0.end }?.text
    }
    public func search(_ query: String) -> [TranscriptCue] {
        cues.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }
    }

    public static func captionCues(from runs: [TimedSpeechRun], maximumCharacters: Int = 80) -> [TranscriptCue] {
        let valid = runs.filter { $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start && $0.end <= 86_400 }
        guard let first = valid.first else { return [] }
        var cues: [TranscriptCue] = [], text = ""
        var start = first.start, end = first.end
        for run in valid {
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               text.count + run.text.count > max(1, maximumCharacters) || run.end - start > 6 {
                cues.append(TranscriptCue(start: start, end: end, text: text.trimmingCharacters(in: .whitespacesAndNewlines)))
                text = ""; start = run.start
            }
            text += run.text; end = run.end
        }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty, end > start { cues.append(TranscriptCue(start: start, end: end, text: clean)) }
        return cues
    }
    public var srt: String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(Self.timestamp(cue.start, separator: ",")) --> \(Self.timestamp(cue.end, separator: ","))\n\(Self.safeCaption(cue.text))\n"
        }.joined(separator: "\n")
    }
    public var vtt: String {
        "WEBVTT\n\n" + cues.map {
            "\(Self.timestamp($0.start, separator: ".")) --> \(Self.timestamp($0.end, separator: "."))\n\(Self.safeCaption($0.text))\n"
        }.joined(separator: "\n")
    }
    private static func safeCaption(_ text: String) -> String {
        text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "-->", with: "→")
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
    private static func timestamp(_ seconds: Double, separator: String) -> String {
        let ms = max(0, Int((seconds * 1_000).rounded()))
        return String(format: "%02d:%02d:%02d%@%03d", ms / 3_600_000, (ms / 60_000) % 60,
                      (ms / 1_000) % 60, separator, ms % 1_000)
    }
}

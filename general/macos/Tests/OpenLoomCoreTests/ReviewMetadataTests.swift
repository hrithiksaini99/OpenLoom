import Foundation
import OpenLoomCore
import Testing

struct ReviewMetadataTests {
    @Test func olderSettingsAndManifestsDecodeWithSafeDefaults() throws {
        let settings = try JSONDecoder().decode(RecordingSettings.self, from: Data("{\"framesPerSecond\":60,\"microphone\":true}".utf8))
        #expect(settings.mode == .screen)
        #expect(settings.cameraID == nil)
        #expect(!settings.captureClicks)
        #expect(settings.microphone && settings.framesPerSecond == 60)
        let original = RecordingManifest(title: "Old recording", source: "Display", settings: settings)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var old = try #require(JSONSerialization.jsonObject(with: encoder.encode(original)) as? [String: Any])
        for key in ["transcript", "notes", "visualEdits", "clicks"] { old.removeValue(forKey: key) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RecordingManifest.self, from: JSONSerialization.data(withJSONObject: old))
        try decoded.validate()
        #expect(decoded.notes.isEmpty && decoded.visualEdits.isEmpty && decoded.clicks.isEmpty)
        #expect(decoded.transcript == nil)
    }

    @Test func captionsKeepTimestampsEscapeMarkupAndSupportSearch() throws {
        let transcript = LocalTranscript(localeIdentifier: "en-US", cues: [
            TranscriptCue(start: 0.125, end: 2.5, text: "Hello local world"),
            TranscriptCue(start: 3_661.234, end: 3_663, text: "<tag>\nA & B --> next"),
        ])
        try transcript.validate()
        #expect(transcript.caption(at: 1) == "Hello local world")
        #expect(transcript.caption(at: 2.5) == nil)
        #expect(transcript.search("LOCAL").count == 1)
        #expect(transcript.srt.contains("00:00:00,125 --> 00:00:02,500"))
        #expect(transcript.srt.contains("01:01:01,234"))
        #expect(transcript.vtt.hasPrefix("WEBVTT\n\n"))
        #expect(transcript.vtt.contains("&lt;tag&gt; A &amp; B → next"))
        #expect(!transcript.vtt.contains("<tag>"))
    }

    @Test func malformedReviewDataIsRejectedBeforeItCanBeSaved() throws {
        #expect(throws: OpenLoomError.self) { try TimedNote(time: .nan, text: "Note", kind: .note).validate() }
        #expect(throws: OpenLoomError.self) { try TranscriptCue(start: 2, end: 1, text: "Backwards").validate() }
        #expect(throws: OpenLoomError.self) { try VisualCue(start: 0, end: 1, tool: .zoom, points: [.init(x: 2, y: 0.5)]).validate() }
        #expect(throws: OpenLoomError.self) { try VisualCue(start: 0, end: 1, tool: .arrow, points: [.init(x: 0, y: 0)]).validate() }
        var manifest = RecordingManifest(title: "Demo", source: "Camera", settings: RecordingSettings())
        manifest.status = .ready; manifest.duration = 1
        manifest.notes = [TimedNote(time: 2, text: "Beyond the video", kind: .chapter)]
        #expect(throws: OpenLoomError.self) { try manifest.validate() }
    }

    @Test func zoomRampsSmoothlyAndRemainsBounded() throws {
        let cue = VisualCue(start: 1, end: 3, tool: .zoom, points: [.init(x: 0.5, y: 0.5)], zoom: 2)
        try cue.validate()
        #expect(cue.zoomFactor(at: 0.9) == 1)
        #expect(cue.zoomFactor(at: 1) == 1)
        #expect(cue.zoomFactor(at: 1.175) > 1 && cue.zoomFactor(at: 1.175) < 2)
        #expect(cue.zoomFactor(at: 2) == 2)
        #expect(cue.zoomFactor(at: 3) == 1)
        let click = CursorClick(time: 0.8, point: .init(x: 0.4, y: 0.6))
        #expect(click.highlight(duration: 1)?.end == 1)
        #expect(click.highlight(duration: 0.5) == nil)
    }

    @Test func captionGroupingKeepsWordSpacingAndIgnoresInvalidRunTimes() throws {
        let cues = LocalTranscript.captionCues(from: [
            TimedSpeechRun(text: "Invalid", start: .nan, end: 1),
            TimedSpeechRun(text: "Hello ", start: 0, end: 1),
            TimedSpeechRun(text: "local ", start: 1, end: 2),
            TimedSpeechRun(text: "world.", start: 2, end: 3),
        ], maximumCharacters: 13)
        #expect(cues.map(\.text) == ["Hello local", "world."])
        #expect(cues[0].start == 0 && cues[0].end == 2)
        #expect(cues[1].start == 2 && cues[1].end == 3)
        for cue in cues { try cue.validate() }
    }

    @Test func localCaptionAndReviewExportsRoundTripWithPrivatePermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = RecordingLibrary(root: root)
        var recording = try library.create(title: "../../A walkthrough", source: "Display", settings: RecordingSettings())
        recording.duration = 5
        recording.notes = [TimedNote(time: 2, text: "Explain the result", kind: .chapter), TimedNote(time: 4, text: "Follow up", kind: .note)]
        recording.transcript = LocalTranscript(localeIdentifier: "en-US", cues: [TranscriptCue(start: 0, end: 1.5, text: "Hello world")])
        try library.save(recording)
        #expect(try library.scan().recordings.first?.transcript?.plainText == "Hello world")
        let captions = try library.exportCaptions(recording)
        #expect(captions.count == 2)
        #expect(try String(contentsOf: captions[0], encoding: .utf8).contains("00:00:01,500"))
        let review = try library.exportReview(recording)
        #expect(try String(contentsOf: review, encoding: .utf8).contains("**00:02** Explain the result"))
        for url in captions + [review] {
            try LocalFilePolicy.requireContained(url, in: root)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
    }
}

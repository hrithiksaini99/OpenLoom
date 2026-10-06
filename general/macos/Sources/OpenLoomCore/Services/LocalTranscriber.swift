@preconcurrency import AVFoundation
import Foundation
import Speech

public struct SpeechLanguage: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
}

/// SpeechTranscriber processes audio on-device. No asset installation or server recognizer is used.
public actor LocalTranscriber {
    public init() {}

    public func installedLanguages() async -> [SpeechLanguage] {
        guard #available(macOS 26, *), SpeechTranscriber.isAvailable else { return [] }
        let locales = await SpeechTranscriber.installedLocales
        return locales.map { locale in
            SpeechLanguage(id: locale.identifier, label: Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
        }.sorted { $0.label < $1.label }
    }

    public func transcribe(audio: URL, language: String, duration: Double,
                           progress: @escaping @Sendable (Double) async -> Void) async throws -> LocalTranscript {
        try LocalFilePolicy.requireLocalFile(audio)
        guard #available(macOS 26, *), SpeechTranscriber.isAvailable else { throw OpenLoomError.speechUnavailable }
        let installed = await SpeechTranscriber.installedLocales
        guard let locale = installed.first(where: { $0.identifier == language }) else { throw OpenLoomError.speechUnavailable }
        let module = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        guard await AssetInventory.status(forModules: [module]) == .installed else { throw OpenLoomError.speechUnavailable }
        try Task.checkCancellation()
        let analyzer = SpeechAnalyzer(modules: [module], options: .init(priority: .utility, modelRetention: .whileInUse))
        let results = Task<[TranscriptCue], any Error> {
            var cues: [TranscriptCue] = []
            for try await result in module.results {
                try Task.checkCancellation()
                guard result.isFinal else { continue }
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                let start = max(0, result.range.start.seconds)
                let end = min(duration, result.range.end.seconds)
                if !text.isEmpty, start.isFinite, end.isFinite, end > start {
                    // Divide long paragraphs at word time attributes when the model provides them.
                    var words: [TimedSpeechRun] = []
                    var prefix = ""
                    for run in result.text.runs {
                        let runText = String(result.text[run.range].characters)
                        if let range = run.audioTimeRange {
                            words.append(TimedSpeechRun(text: prefix + runText, start: max(0, range.start.seconds), end: min(duration, range.end.seconds)))
                            prefix = ""
                        } else if !words.isEmpty { words[words.count - 1].text += runText }
                        else { prefix += runText }
                    }
                    if words.isEmpty {
                        cues.append(TranscriptCue(start: start, end: end, text: text))
                    } else {
                        cues.append(contentsOf: LocalTranscript.captionCues(from: words))
                    }
                }
                await progress(end)
            }
            return cues.sorted { $0.start < $1.start }
        }
        return try await withTaskCancellationHandler {
            do {
                let file = try AVAudioFile(forReading: audio)
                _ = try await analyzer.analyzeSequence(from: file)
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                let transcript = LocalTranscript(localeIdentifier: language, cues: try await results.value)
                try transcript.validate()
                return transcript
            } catch {
                results.cancel()
                await analyzer.cancelAndFinishNow()
                throw error
            }
        } onCancel: {
            results.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }
}

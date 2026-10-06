import OpenLoomCore
import SwiftUI

struct ReviewPane: View {
    @Bindable var model: AppModel
    let recording: RecordingManifest
    @Bindable var playback: PlaybackController
    @ViewState private var tab = 0
    @ViewState private var query = ""
    @ViewState private var editingNote: TimedNote?
    @ViewState private var editingCue: TranscriptCue?

    init(model: AppModel, recording: RecordingManifest, playback: PlaybackController, initialTab: Int = 0) {
        self.model = model; self.recording = recording; self.playback = playback
        _tab = ViewState(wrappedValue: initialTab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Review").font(.headline)
                Spacer()
                LocalStorageBadge()
            }
            Picker("Review tools", selection: $tab) {
                Text("Transcript").tag(0)
                Text("Chapters & notes").tag(1)
            }.pickerStyle(.segmented).labelsHidden()
            if tab == 0 { transcript } else { notes }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(item: $editingNote) { note in NoteEditorView(model: model, recording: recording, note: note) }
        .sheet(item: $editingCue) { cue in CaptionEditorView(model: model, recording: recording, cue: cue) }
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let transcript = recording.transcript {
                HStack {
                    Text("\(transcript.cues.count) captions").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Show on video", isOn: $playback.captionsEnabled).toggleStyle(.checkbox).font(.caption)
                }
                TextField("Find spoken words", text: $query).textFieldStyle(.roundedBorder)
                let cues = transcript.search(query)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(cues) { cue in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Button(Formatters.duration(cue.start)) { playback.seek(to: cue.start) }
                                        .font(.caption.monospacedDigit()).buttonStyle(.borderless)
                                    Spacer()
                                    Button("Edit caption", systemImage: "pencil") { editingCue = cue }
                                        .labelStyle(.iconOnly).buttonStyle(.borderless).disabled(model.isBusy)
                                }
                                Text(cue.text).font(.callout).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .background(cue.start <= playback.time && playback.time < cue.end ? Color.accentColor.opacity(0.1) : Color(nsColor: .windowBackgroundColor),
                                        in: .rect(cornerRadius: 8))
                        }
                        if cues.isEmpty {
                            Text(query.isEmpty ? "No speech was detected." : "No matching words.")
                                .font(.callout).foregroundStyle(.secondary).padding(.vertical, 16)
                        }
                    }
                }.frame(maxHeight: .infinity)
                Divider()
                HStack {
                    Button("Export SRT / VTT", systemImage: "square.and.arrow.down") { model.exportCaptions(recording) }
                    Spacer(minLength: 0)
                    Menu {
                        Button("Regenerate captions") { model.generateCaptions(recording) }
                            .disabled(model.isBusy || model.speechLanguages.isEmpty)
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize()
                }.controlSize(.small)
                Text(transcript.engine.contains("Generated") ? "Sample captions from the generated demo." : "Captions generated on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "captions.bubble").font(.title).foregroundStyle(.secondary)
                    Text("Find any moment").font(.headline)
                    Text("Generate captions to search spoken words and jump to the matching time.")
                        .font(.callout).foregroundStyle(.secondary)
                    if model.speechLanguages.isEmpty {
                        Text("Requires macOS 26+ and a speech language already installed on this Mac.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Check installed languages") { Task { await model.refreshSpeechLanguages() } }
                            .controlSize(.small).disabled(model.isBusy)
                    } else {
                        Picker("Language", selection: $model.speechLanguage) {
                            ForEach(model.speechLanguages) { Text($0.label).tag($0.id) }
                        }
                        Button("Generate captions", systemImage: "captions.bubble") { model.generateCaptions(recording) }
                            .buttonStyle(.borderedProminent).disabled(model.isBusy)
                    }
                    Text("Speech is processed locally. No model downloads or uploads.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 16)
                Spacer(minLength: 0)
            }
        }.frame(maxHeight: .infinity, alignment: .top)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("At \(Formatters.duration(playback.time))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            HStack {
                Button("Chapter", systemImage: "bookmark") { editingNote = TimedNote(time: min(playback.time, recording.duration), text: "", kind: .chapter) }
                Button("Note", systemImage: "note.text") { editingNote = TimedNote(time: min(playback.time, recording.duration), text: "", kind: .note) }
                Spacer(minLength: 0)
            }.disabled(model.isBusy)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(recording.notes.sorted { $0.time < $1.time }) { note in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: note.kind == .chapter ? "bookmark" : "note.text").foregroundStyle(.secondary)
                                Button(Formatters.duration(note.time)) { playback.seek(to: note.time) }
                                    .font(.caption.monospacedDigit()).buttonStyle(.borderless)
                                Spacer()
                                Menu {
                                    Button("Edit") { editingNote = note }
                                    Button("Delete", role: .destructive) { model.removeNote(for: recording.id, noteID: note.id) }
                                } label: { Image(systemName: "ellipsis") }
                                .menuStyle(.borderlessButton).fixedSize().disabled(model.isBusy)
                            }
                            Text(note.text).font(note.kind == .chapter ? .callout.weight(.semibold) : .callout)
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(12).background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: 8))
                    }
                    if recording.notes.isEmpty {
                        Text("Add a chapter or note at the current playback time. You can also mark chapters while recording with ⇧⌘M.")
                            .font(.callout).foregroundStyle(.secondary).padding(.vertical, 16)
                    }
                }
            }.frame(maxHeight: .infinity)
            Divider()
            Button("Export review document", systemImage: "doc.text") { model.exportReview(recording) }.controlSize(.small)
        }.frame(maxHeight: .infinity, alignment: .top)
    }
}

struct NoteEditorView: View {
    let model: AppModel
    let recording: RecordingManifest
    let note: TimedNote
    @Environment(\.dismiss) private var dismiss
    @ViewState private var text: String
    @ViewState private var time: Double
    @ViewState private var kind: NoteKind
    init(model: AppModel, recording: RecordingManifest, note: TimedNote) {
        self.model = model; self.recording = recording; self.note = note
        _text = ViewState(wrappedValue: note.text); _time = ViewState(wrappedValue: note.time); _kind = ViewState(wrappedValue: note.kind)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Chapter or review note").font(.title2.bold())
            Picker("Type", selection: $kind) { ForEach(NoteKind.allCases, id: \.self) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
            HStack { Text("Time (seconds)"); TextField("Time", value: $time, format: .number).frame(width: 110) }
            TextEditor(text: $text).frame(height: 130).border(.quaternary)
            HStack {
                Text("Saved only in this recording’s local metadata.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") { model.saveNote(for: recording.id, noteID: note.id, time: time, text: text, kind: kind); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2_000 || !time.isFinite || time < 0 || time > recording.duration)
            }
        }.padding(24).frame(width: 530)
    }
}

struct CaptionEditorView: View {
    let model: AppModel
    let recording: RecordingManifest
    let cue: TranscriptCue
    @Environment(\.dismiss) private var dismiss
    @ViewState private var text: String
    init(model: AppModel, recording: RecordingManifest, cue: TranscriptCue) {
        self.model = model; self.recording = recording; self.cue = cue
        _text = ViewState(wrappedValue: cue.text)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Correct caption").font(.title2.bold())
            Text("\(Formatters.duration(cue.start)) – \(Formatters.duration(cue.end))").foregroundStyle(.secondary)
            TextEditor(text: $text).frame(height: 120).border(.quaternary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    var updated = cue; updated.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.saveCaption(for: recording.id, cue: updated); dismiss()
                }.buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 10_000)
            }
        }.padding(24).frame(width: 530)
    }
}

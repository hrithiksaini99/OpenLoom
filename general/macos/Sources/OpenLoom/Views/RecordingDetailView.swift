import AVKit
import OpenLoomCore
import SwiftUI

struct RecordingDetailView: View {
    @Bindable var model: AppModel
    let recording: RecordingManifest
    @ViewState private var playback = PlaybackController()
    @ViewState private var newTitle = ""
    @ViewState private var renaming = false
    @ViewState private var showTrim = false
    @ViewState private var showPolish = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recording.title).font(.title2.weight(.semibold)).lineLimit(2).textSelection(.enabled)
                    Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if recording.status == .ready {
                    Menu {
                        Button("Show original MP4") { model.reveal(model.library.outputURL(for: recording.id)) }
                        Button("Show all source files") { model.reveal(model.library.folder(for: recording.id)) }
                        Divider()
                        Button("Rename…") { newTitle = recording.title; renaming = true }
                        Button("Export captions (SRT / VTT)") { model.exportCaptions(recording) }.disabled(recording.transcript == nil)
                        Button("Export notes & transcript") { model.exportReview(recording) }
                    } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                    .menuStyle(.borderlessButton).fixedSize().help("Recording actions")
                }
            }.padding(24)
            Divider()
            if recording.status == .ready {
                HSplitView {
                    playerWorkspace.frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    ReviewPane(model: model, recording: recording, playback: playback)
                        .frame(minWidth: 280, idealWidth: 320, maxWidth: 380, maxHeight: .infinity)
                }
                .task(id: recording.status) {
                    do {
                        try playback.load(url: model.library.outputURL(for: recording.id), root: model.library.root)
                        let arguments = ProcessInfo.processInfo.arguments
                        if arguments.contains("--studio-check") || arguments.contains("--camera-lifecycle-check") || arguments.contains("--screen-lifecycle-check") {
                            model.acceptancePlayer = playback
                        }
                    }
                    catch { model.errorMessage = error.localizedDescription }
                }
            } else { recoveryWorkspace }
        }
        .navigationTitle(recording.title)
        .onDisappear {
            if model.acceptancePlayer === playback { model.acceptancePlayer = nil }
            playback.detach()
        }
        .sheet(isPresented: $showTrim) { TrimExportView(model: model, recording: recording) }
        .sheet(isPresented: $showPolish) { VisualEditorView(model: model, recording: recording) }
        .alert("Rename recording", isPresented: $renaming) {
            TextField("Title", text: $newTitle)
            Button("Save") { model.rename(recording, to: newTitle) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var playerWorkspace: some View {
        VStack(alignment: .leading, spacing: 20) {
            ZStack {
                NativeVideoPlayer(player: playback.player)
                if playback.captionsEnabled, let caption = recording.transcript?.caption(at: playback.time) {
                    VStack {
                        Spacer()
                        Text(caption).font(.system(size: 16, weight: .medium)).multilineTextAlignment(.center)
                            .foregroundStyle(.white).padding(10)
                            .background(.black.opacity(0.8), in: .rect(cornerRadius: 6))
                            .padding(.horizontal, 16).padding(.bottom, 52)
                    }.allowsHitTesting(false)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(.black).clipShape(.rect(cornerRadius: 12))
            HStack(spacing: 16) {
                Label(Formatters.duration(recording.duration), systemImage: "clock")
                Text("\(recording.settings.resolution.label) · \(recording.settings.framesPerSecond) fps")
            }.font(.caption).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { editActions }
                VStack(alignment: .leading, spacing: 10) { editActions }
            }.disabled(model.isBusy)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Label("Original saved", systemImage: "checkmark.circle").font(.subheadline.weight(.medium))
                Text("Trim and edit exports create a separate video. Your recording and source takes stay in the library.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Show MP4 in Finder", systemImage: "folder") { model.reveal(model.library.outputURL(for: recording.id)) }
                    .buttonStyle(.borderless).font(.callout)
            }
            Spacer(minLength: 0)
        }.padding(24)
    }

    @ViewBuilder private var editActions: some View {
        Button("Trim", systemImage: "scissors") { playback.player.pause(); showTrim = true }
        Button("Edit video", systemImage: "wand.and.stars") { playback.player.pause(); showPolish = true }
            .buttonStyle(.borderedProminent)
            .help("Draw, highlight clicks, and add zoom")
    }

    private var recoveryWorkspace: some View {
        ContentUnavailableView {
            Label(model.recorder.manifest?.id == recording.id ? "Recording in progress" : "Recover your recording",
                  systemImage: "tray.and.arrow.down")
        } description: {
            Text(recording.segmentDurations.isEmpty
                 ? "Recovery checks the source files saved in this session. A take interrupted before it finished writing may be incomplete."
                 : "\(recording.segmentDurations.count) completed take(s) are saved. Recover them into a playable video.")
        } actions: {
            Button("Recover saved takes") { Task { await model.recover(recording) } }
                .buttonStyle(.borderedProminent)
                .disabled(!model.library.hasCaptureFiles(for: recording) || model.isBusy)
            if recording.settings.mode == .screenAndCamera {
                Button("Recover screen only") { Task { await model.recover(recording, includeCamera: false) } }
                    .disabled(!model.library.hasCaptureFiles(for: recording) || model.isBusy)
            }
            Button("Show source files") { model.reveal(model.library.folder(for: recording.id)) }
        }
    }
}

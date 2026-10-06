import SwiftUI

/// Lives outside scrolling setup/review content, including while browsing another recording.
struct CaptureTransport: View {
    @Bindable var model: AppModel
    private var recorder: CaptureEngine { model.recorder }

    var body: some View {
        VStack(spacing: 12) {
            if recorder.phase.isProcessing {
                HStack {
                    Text(recorder.processingMessage).font(.callout)
                    Spacer()
                    if let fraction = recorder.processingProgress {
                        Text("\(Int(fraction * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: recorder.processingProgress)
            }
            HStack(spacing: 16) {
                HStack(spacing: 10) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 4) {
                        if recorder.phase.isSessionActive {
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                Text("\(statusTitle) · \(Formatters.duration(recorder.elapsed))")
                                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                            }
                        } else { Text(statusTitle).font(.subheadline.weight(.semibold)) }
                        Text(statusDetail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 12)
                controls
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder private var controls: some View {
        switch recorder.phase {
        case .recording, .paused:
            Button("Mark chapter", systemImage: "bookmark") { recorder.addChapter() }
                .labelStyle(.iconOnly).help("Mark chapter (⇧⌘M)")
            Button(recorder.phase == .paused ? "Resume" : "Pause", systemImage: recorder.phase == .paused ? "play.fill" : "pause.fill") {
                Task {
                    if recorder.phase == .paused { await recorder.resume() }
                    else { await recorder.pause() }
                }
            }.help("Pause or resume (⇧⌘P)")
            Button("Stop & save", systemImage: "stop.fill") { Task { await recorder.stop() } }
                .buttonStyle(.borderedProminent).tint(StudioStyle.recordingAction).buttonBorderShape(.capsule).controlSize(.large)
                .help("Stop and save (⇧⌘S)")
        case .pausing, .finishing:
            if let session = recorder.manifest {
                Button("Show source files", systemImage: "folder") { model.reveal(model.library.folder(for: session.id)) }
                    .labelStyle(.iconOnly)
            }
            Button(recorder.isCancellingProcessing ? "Cancelling…" : "Cancel processing") { recorder.cancelProcessing() }
                .disabled(recorder.isCancellingProcessing)
        case .countdown:
            Button("Cancel countdown", role: .cancel) { recorder.cancelCountdown() }
        case .starting:
            ProgressView().controlSize(.small)
            if recorder.manifest == nil { Button("Cancel", role: .cancel) { recorder.cancelCountdown() } }
        case .failed:
            Button("Reset recorder") { recorder.modeDidChange() }
        default:
            Button { Task { await recorder.start() } } label: {
                Label("Record", systemImage: "record.circle.fill").frame(minWidth: 100)
            }
            .buttonStyle(.borderedProminent).tint(StudioStyle.recordingAction).buttonBorderShape(.capsule).controlSize(.large)
            .disabled(!recorder.canStart || model.isBusy || model.isRunningUICheck)
            .help("Start recording (⇧⌘R)")
        }
    }

    private var statusTitle: String {
        switch recorder.phase {
        case .idle: "Choose a source"
        case .ready: recorder.canStart ? "Ready to record" : "Check your camera"
        case .recording: "Recording"
        case .paused: "Paused"
        case .pausing, .finishing: "Saving"
        case .failed: "Recording interrupted"
        default: recorder.phase.label
        }
    }
    private var statusDetail: String {
        if recorder.phase.isProcessing { return "Cancel keeps finalized source files for recovery." }
        if recorder.phase == .paused { return "Current take saved locally." }
        if case .failed = recorder.phase { return "Review saved sources in the library, or reset to record again." }
        if recorder.settings.mode.usesCamera, recorder.camera.requiresRestart { return "Restart OpenLoom to release the camera." }
        if recorder.settings.mode.usesCamera, recorder.camera.devices.isEmpty { return "No camera found. Connect a camera or choose Screen." }
        return "\(recorder.settings.resolution.label) · \(recorder.settings.framesPerSecond) fps · Microphone \(recorder.settings.microphone ? "on" : "off")"
    }
    private var statusColor: Color {
        switch recorder.phase {
        case .recording: .red
        case .ready: recorder.canStart ? .green : .orange
        case .failed: .orange
        default: .secondary
        }
    }
}

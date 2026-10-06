import OpenLoomCore
import SwiftUI

/// Shared recorder state; this window never owns a capture engine or session.
struct FloatingRecorderView: View {
    @Bindable var model: AppModel
    var fixturePhase: RecordingPhase?
    var fixtureElapsed: Double?
    private var recorder: CaptureEngine { model.recorder }
    private var phase: RecordingPhase { fixturePhase ?? recorder.phase }

    var body: some View {
        @Bindable var recorder = model.recorder
        @Bindable var floating = model.floating
        HStack(spacing: 12) {
            OpenLoomMark(size: 40, active: phase == .recording)
                .help("Drag the background to move this recorder")
            VStack(alignment: .leading, spacing: 4) {
                if phase.isSessionActive {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(Formatters.duration(fixtureElapsed ?? recorder.elapsed))
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    }
                } else { Text("OpenLoom").font(.system(size: 15, weight: .semibold, design: .rounded)) }
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.frame(width: 105, alignment: .leading)
            Divider().frame(height: 30)
            if phase.isProcessing {
                ProgressView().controlSize(.small)
                Button("Cancel", role: .cancel) { recorder.cancelProcessing() }.disabled(recorder.isCancellingProcessing)
            } else {
                if !phase.isSessionActive {
                    Button { recorder.settings.microphone.toggle() } label: {
                        Image(systemName: recorder.settings.microphone ? "mic.fill" : "mic.slash")
                    }.buttonStyle(.borderless).help(recorder.settings.microphone ? "Turn microphone off" : "Turn microphone on")
                        .disabled(model.isBusy || model.isRunningUICheck)
                }
                Group {
                    Button { Task { await model.toggleFloatingCamera() } } label: {
                        Image(systemName: model.floating.isCameraVisible ? "video.fill" : "video")
                    }.buttonStyle(.borderless)
                        .help(model.floating.isCameraVisible ? "Hide camera preview; camera recording continues" : "Show draggable camera preview")
                        .disabled(recorder.camera.isPreparing || recorder.camera.requiresRestart || model.isRunningUICheck || (recorder.phase.isSessionActive && !recorder.settings.mode.usesCamera))
                }
                switch phase {
                case .recording, .paused:
                    Button { recorder.addChapter() } label: { Image(systemName: "bookmark") }
                        .buttonStyle(.borderless).help("Mark chapter")
                    Button {
                        Task { if phase == .paused { await recorder.resume() } else { await recorder.pause() } }
                    } label: { Image(systemName: phase == .paused ? "play.fill" : "pause.fill").frame(width: 30, height: 30) }
                    .buttonStyle(.bordered).buttonBorderShape(.circle)
                    Button { Task { await recorder.stop() } } label: {
                        Image(systemName: "stop.fill").foregroundStyle(.white).frame(width: 34, height: 34)
                            .background(StudioStyle.recordingAction, in: .circle)
                    }.buttonStyle(.plain).help("Stop and save locally")
                case .countdown:
                    Button("Cancel") { recorder.cancelCountdown() }
                case .starting, .choosingSource:
                    ProgressView().controlSize(.small)
                case .failed:
                    Button("Reset") { recorder.modeDidChange() }
                default:
                    Button {
                        if recorder.settings.mode.usesScreen && !recorder.hasScreenSource { recorder.chooseSource() }
                        else { Task { await recorder.start() } }
                    } label: {
                        Label(recorder.settings.mode.usesScreen && !recorder.hasScreenSource ? "Source" : "Record", systemImage: "record.circle.fill")
                            .font(.subheadline.weight(.semibold)).padding(.horizontal, 4)
                    }.buttonStyle(.borderedProminent).tint(StudioStyle.recordingAction).buttonBorderShape(.capsule)
                        .disabled(model.isBusy || model.isRunningUICheck || recorder.camera.requiresRestart
                                  || (!(recorder.settings.mode.usesScreen && !recorder.hasScreenSource) && !recorder.canStart))
                }
            }
            Menu {
                Button("Open studio", systemImage: "macwindow") { model.showLibrary() }
                if recorder.settings.mode.usesScreen {
                    Button("Choose source…", systemImage: "rectangle.on.rectangle") { recorder.chooseSource() }
                        .disabled(!recorder.phase.canChooseSource || model.isBusy)
                }
                if !recorder.phase.isSessionActive {
                    Picker("Recording mode", selection: $recorder.settings.mode) {
                        ForEach(CaptureMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.disabled(model.isBusy || model.isRunningUICheck)
                }
                if model.floating.isCameraVisible {
                    Picker("Preview size", selection: $floating.cameraSize) {
                        Text("Small").tag(180.0); Text("Medium").tag(240.0); Text("Large").tag(300.0)
                    }
                }
                Divider()
                Button("Hide floating controls", systemImage: "xmark") { model.floating.hideRecorder() }
            } label: { Image(systemName: "ellipsis").frame(width: 22, height: 30) }
            .menuStyle(.borderlessButton).fixedSize().help("Floating recorder options")
        }
        .controlSize(.regular)
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(width: 470, height: 78)
        .modifier(FloatingGlass())
        .padding(6)
        .tint(StudioStyle.violet)
    }

    private var status: String {
        if phase.isProcessing { return "Saving on this Mac" }
        switch phase {
        case .recording: return "Recording · local only"
        case .paused: return "Paused · take saved"
        case .failed: return "Needs attention"
        case .ready: return recorder.settings.mode.label
        case .idle: return "Choose a source"
        default: return phase.label
        }
    }
}

struct FloatingCameraView: View {
    @Bindable var model: AppModel
    @ViewState private var hovering = false

    var body: some View {
        ZStack {
            Circle().fill(StudioStyle.gradient)
            if let frame = model.recorder.camera.previewFrame {
                CameraPreview(frame: frame, mirrored: model.recorder.settings.mirrorCamera)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    OpenLoomMark(size: 58)
                    if model.recorder.camera.isPreparing { ProgressView().tint(.white) }
                    Text(model.recorder.camera.errorMessage == nil ? "Camera preview" : "Preview unavailable")
                        .font(.caption.weight(.medium)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.65), in: .capsule)
                }
            }
        }
        .clipShape(.circle)
        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 3))
        .overlay(alignment: .topTrailing) {
            Button { Task { await model.hideFloatingCamera() } } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28).background(.black.opacity(0.65), in: .circle)
            }.buttonStyle(.plain).padding(18).opacity(hovering ? 1 : 0)
                .help("Hide preview; recording continues")
        }
        .onHover { hovering = $0 }
        .padding(6)
        .accessibilityLabel("Draggable camera preview. Recorded bubble position uses the Camera settings.")
        .help("Drag to move this preview. Set the recorded bubble position in Camera settings.")
    }
}

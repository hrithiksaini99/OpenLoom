import OpenLoomCore
import SwiftUI

struct CaptureSourceView: View {
    @Bindable var model: AppModel
    private var recorder: CaptureEngine { model.recorder }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                RadialGradient(colors: [StudioStyle.violet.opacity(0.1), StudioStyle.coral.opacity(0.04), .clear], center: .center, startRadius: 20, endRadius: 320)
                if (recorder.camera.isPreviewing || recorder.camera.isShowingRecordingPreview) && recorder.settings.mode == .camera {
                    CameraPreview(frame: recorder.camera.previewFrame, mirrored: recorder.settings.mirrorCamera)
                        .accessibilityLabel("Live camera preview")
                } else {
                    canvasState.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if (recorder.camera.isPreviewing || recorder.camera.isShowingRecordingPreview) && recorder.settings.mode == .screenAndCamera {
                    CameraPreview(frame: recorder.camera.previewFrame, mirrored: recorder.settings.mirrorCamera)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(width: 128)
                        .clipShape(.rect(cornerRadius: 12))
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: cameraAlignment)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Label(recorder.sourceLabel, systemImage: recorder.settings.mode.symbol)
                    .font(.subheadline.weight(.medium)).lineLimit(2)
                HStack(spacing: 8) {
                    if recorder.settings.mode.usesScreen {
                        Button(recorder.hasScreenSource ? "Change source" : "Choose source", systemImage: "rectangle.on.rectangle") { recorder.chooseSource() }
                            .disabled(!recorder.phase.canChooseSource || model.isBusy || model.isRunningUICheck)
                    }
                    if recorder.settings.mode.usesCamera {
                        Button(recorder.camera.isPreviewing ? "Close preview" : "Preview camera", systemImage: "video") {
                            Task {
                                if recorder.camera.isPreviewing { await recorder.camera.stopPreview() }
                                else { await recorder.camera.preview(settings: recorder.settings) }
                            }
                        }
                        .disabled(recorder.phase.isSessionActive || recorder.camera.isPreparing || recorder.camera.requiresRestart || recorder.camera.devices.isEmpty)
                    }
                    if recorder.camera.isPreparing { ProgressView().controlSize(.small) }
                    Spacer(minLength: 0)
                }.controlSize(.regular)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
        }
        .clipShape(.rect(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.quaternary, lineWidth: 1))
    }

    @ViewBuilder private var canvasState: some View {
        switch recorder.phase {
        case .countdown(let seconds):
            VStack(spacing: 12) {
                Text("\(seconds)").font(.system(size: 76, weight: .semibold, design: .rounded))
                Text("Get ready").foregroundStyle(.secondary)
            }
        case .recording, .paused, .pausing, .finishing:
            VStack(spacing: 16) {
                Label(recorder.phase.isProcessing ? "Saving your recording" : recorder.phase == .paused ? "Recording paused" : "Recording in progress",
                      systemImage: recorder.phase.isProcessing ? "tray.and.arrow.down" : recorder.phase == .paused ? "pause.circle" : "record.circle.fill")
                    .font(.headline).foregroundStyle(recorder.phase == .recording ? .red : .secondary)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(Formatters.duration(recorder.elapsed)).font(.system(size: 46, weight: .medium, design: .monospaced))
                }
                Text(recorder.phase == .paused ? "This take is saved. Resume when you're ready." : "Use the controls below or the menu bar to pause and stop.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        case .failed(let reason):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                Text("Recording interrupted").font(.headline)
                Text(reason).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).textSelection(.enabled)
                if let id = recorder.lastInterruptedID {
                    Button("Review saved sources") { model.selectedID = id }
                }
            }
        case .starting, .choosingSource:
            VStack(spacing: 16) {
                ProgressView()
                Text(recorder.phase.label).font(.callout).foregroundStyle(.secondary)
            }
        default:
            VStack(spacing: 14) {
                Image(systemName: recorder.settings.mode.symbol)
                    .font(.system(size: 46, weight: .light)).foregroundStyle(StudioStyle.violet.opacity(0.8))
                Text(recorder.settings.mode == .camera ? "Camera preview is off" : recorder.hasScreenSource ? "Source selected" : "Choose your screen or window")
                    .font(.headline)
                Text(recorder.settings.mode == .camera
                     ? "Preview your camera here, or press Record to begin."
                     : recorder.hasScreenSource
                        ? "Your selected source is ready. Screen capture begins when you press Record."
                        : "Use the macOS picker to choose exactly what you want to record.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var cameraAlignment: Alignment {
        switch recorder.settings.cameraPosition {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }
}

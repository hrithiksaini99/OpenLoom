import OpenLoomCore
import SwiftUI

struct CaptureSetupView: View {
    @Bindable var model: AppModel

    var body: some View {
        @Bindable var recorder = model.recorder
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(recorder.phase.isSessionActive ? "Recording studio" : "New recording")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                        Text("Choose a source, check your audio, and record.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    LocalStorageBadge()
                }
                CaptureModeSelector(selection: $recorder.settings.mode)
                    .disabled(model.isBusy || model.isRunningUICheck)

                HStack(alignment: .top, spacing: 20) {
                    sourceColumn.frame(minWidth: 0, maxWidth: .infinity)
                    CaptureOptionsView(recorder: recorder).frame(width: 260)
                }

                if !recorder.phase.isSessionActive {
                    HStack {
                        Image(systemName: "play.rectangle").foregroundStyle(.secondary)
                        Text("Explore captions, notes, and video editing with a generated sample.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button("Open demo") { Task { await model.createDemo() } }
                            .disabled(model.isBusy)
                    }
                }
            }
            .frame(maxWidth: 1120, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("New recording")
        .onDisappear {
            if !recorder.phase.isSessionActive && !model.floating.isCameraVisible { Task { await recorder.camera.stopPreview() } }
        }
    }

    private var sourceColumn: some View {
        @Bindable var recorder = model.recorder
        return VStack(alignment: .leading, spacing: 16) {
            CaptureSourceView(model: model)
            VStack(alignment: .leading, spacing: 8) {
                Text("Recording name").font(.subheadline.weight(.medium))
                TextField("Untitled recording", text: $recorder.title)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.recorder.phase.isSessionActive)
            }
            Text("Videos are saved automatically in your local library. Pause finishes the current take; stop creates the reviewable video.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

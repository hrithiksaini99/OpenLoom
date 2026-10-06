import SwiftUI

struct RecordingMenu: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if model.recorder.phase.isSessionActive {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text("\(model.recorder.phase.isProcessing ? "Saving" : model.recorder.phase == .paused ? "Paused" : "Recording") · \(Formatters.duration(model.recorder.elapsed))")
            }
            if model.recorder.phase == .recording {
                Button("Pause recording") { Task { await model.recorder.pause() } }
            }
            if model.recorder.phase == .paused {
                Button("Resume recording") { Task { await model.recorder.resume() } }
            }
            if model.recorder.phase == .recording || model.recorder.phase == .paused {
                Button("Mark chapter") { model.recorder.addChapter() }
            }
            Button("Stop and save") { Task { await model.recorder.stop() } }
                .disabled(model.recorder.phase != .recording && model.recorder.phase != .paused)
            if model.recorder.phase.isProcessing {
                Text(model.recorder.processingMessage)
                Button("Cancel processing") { model.recorder.cancelProcessing() }
                    .disabled(model.recorder.isCancellingProcessing)
            }
            if case .countdown = model.recorder.phase {
                Button("Cancel countdown") { model.recorder.cancelCountdown() }
            }
            Divider()
        }
        Button("Open library") { openWindow(id: "library"); model.showLibrary() }
        Button("New recording") { model.selectedID = nil; openWindow(id: "library"); model.showLibrary() }
        if model.recorder.phase == .ready {
            Button("Start recording") { Task { await model.recorder.start() } }
                .disabled(!model.recorder.canStart || model.isBusy)
        }
        SettingsLink { Text("Settings…") }
        Divider()
        Text("Local only · network disabled")
        Button("Quit OpenLoom") { NSApp.terminate(nil) }
    }
}

import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(model: model)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            VStack(spacing: 0) {
                LocalTaskBanner(model: model)
                if let notice = model.notice {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                        Text(notice).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                        Button("Dismiss", systemImage: "xmark") { model.notice = nil }
                            .labelStyle(.iconOnly).buttonStyle(.plain)
                    }.padding(.horizontal, 24).padding(.vertical, 12).background(.quaternary.opacity(0.4))
                }
                if let warning = model.libraryWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange).padding(12)
                }
                if let recording = model.selected {
                    RecordingDetailView(model: model, recording: recording).id(recording.id)
                } else { CaptureSetupView(model: model) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsTransport { CaptureTransport(model: model) }
            }
        }
        .toolbar {
            ToolbarItem {
                Button("New recording", systemImage: "plus") { model.selectedID = nil }
                    .help("New recording (⌘N)")
            }
            ToolbarItem { SettingsLink { Image(systemName: "gearshape") } }
            ToolbarItem {
                Button("Floating recorder", systemImage: "rectangle.bottomthird.inset.filled") {
                    if model.floating.isVisible { model.floating.hideRecorder() }
                    else { model.floating.showRecorder(model: model) }
                }.help("Show or hide floating controls (⌥⌘R)")
            }
        }
        .tint(StudioStyle.violet)
        .onAppear {
            model.openStudioWindow = { openWindow(id: "library") }
            if !model.floating.isVisible { model.floating.showRecorder(model: model) }
        }
        .alert("OpenLoom", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert("A local task is still active", isPresented: $model.quitRequested) {
            if model.recorder.phase.isProcessing || model.isRecovering || model.canCancelExport {
                Button("Stop processing and quit") {
                    Task {
                        await model.recorder.cancelProcessingAndWait()
                        await model.cancelRecoveryAndWait()
                        await model.cancelExportAndWait()
                        if !model.isBusy { NSApp.terminate(nil) }
                    }
                }
            }
            if model.recorder.phase == .recording || model.recorder.phase == .paused {
                Button("Save recording and quit") {
                    Task {
                        await model.recorder.stop()
                        if !model.recorder.phase.isSessionActive { NSApp.terminate(nil) }
                    }
                }
            }
            Button("Keep OpenLoom open", role: .cancel) {}
        } message: {
            Text("Finalized source files are kept when processing is cancelled. Finish or cancel the active task before quitting.")
        }
    }

    private var showsTransport: Bool {
        if case .failed = model.recorder.phase { return true }
        return model.selectedID == nil || model.recorder.phase.isSessionActive
    }
}

private struct LocalTaskBanner: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.isRecovering || model.isTranscribing || model.isExporting {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(message).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                    if let fraction { Text("\(Int(fraction * 100))%").font(.caption.monospacedDigit()) }
                    if model.isRecovering { Button("Cancel recovery") { model.cancelRecovery() } }
                    else if model.isTranscribing { Button("Cancel captions") { model.cancelTranscription() } }
                    else if model.canCancelExport { Button("Cancel export") { model.cancelExport() } }
                }
                if fraction != nil { ProgressView(value: fraction) }
            }.padding(.horizontal, 24).padding(.vertical, 12).background(.quaternary.opacity(0.4))
        }
    }
    private var message: String {
        if model.isRecovering { return model.recoveryProgress }
        if model.isTranscribing { return model.transcriptionProgress }
        return model.exportProgress.isEmpty ? "Creating local demo…" : model.exportProgress
    }
    private var fraction: Double? { model.isRecovering ? model.recoveryFraction : model.isExporting ? model.exportFraction : nil }
}

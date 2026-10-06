import AppKit
import SwiftUI

@main
struct OpenLoomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ViewState private var model = AppModel()
    @ViewState private var acceptanceCheckStarted = false

    var body: some Scene {
        Window("OpenLoom", id: "library") {
            ContentView(model: model)
                .frame(minWidth: 980, minHeight: 660)
                .onAppear {
                    delegate.model = model
                    if !acceptanceCheckStarted, ProcessInfo.processInfo.arguments.contains("--camera-lifecycle-check") {
                        acceptanceCheckStarted = true
                        Task { await CameraAcceptanceCheck.run(model: model) }
                    } else if !acceptanceCheckStarted, ProcessInfo.processInfo.arguments.contains("--screen-lifecycle-check") {
                        acceptanceCheckStarted = true
                        Task { await ScreenAcceptanceCheck.run(model: model) }
                    } else if !acceptanceCheckStarted, ProcessInfo.processInfo.arguments.contains("--studio-check") {
                        acceptanceCheckStarted = true
                        Task { await StudioAcceptanceCheck.run(model: model) }
                    }
                }
                .onChange(of: model.recorder.settings) { model.saveSettings() }
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Recording") { model.selectedID = nil; model.showLibrary() }
                    .keyboardShortcut("n")
            }
            CommandMenu("Recording") {
                Button("Show / Hide Floating Recorder") {
                    if model.floating.isVisible { model.floating.hideRecorder() }
                    else { model.floating.showRecorder(model: model) }
                }.keyboardShortcut("r", modifiers: [.command, .option])
                Divider()
                Button("Choose Source…") { model.selectedID = nil; model.recorder.chooseSource() }
                    .disabled(!model.recorder.phase.canChooseSource || model.isRunningUICheck)
                Button("Start Recording") { Task { await model.recorder.start() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!model.recorder.canStart || model.isBusy || model.isRunningUICheck)
                Button("Pause / Resume") {
                    Task {
                        if model.recorder.phase == .paused { await model.recorder.resume() }
                        else { await model.recorder.pause() }
                    }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(model.recorder.phase != .paused && model.recorder.phase != .recording)
                Button("Mark Chapter") { model.recorder.addChapter() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                    .disabled(model.recorder.phase != .paused && model.recorder.phase != .recording)
                Button("Stop Recording") { Task { await model.recorder.stop() } }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(model.recorder.phase != .paused && model.recorder.phase != .recording)
            }
        }

        MenuBarExtra {
            RecordingMenu(model: model)
        } label: {
            Image(systemName: model.recorder.phase == .recording ? "record.circle.fill" : "record.circle")
                .accessibilityLabel("OpenLoom recording controls")
        }

        Settings {
            SettingsView(model: model)
                .frame(width: 460)
                .padding(24)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let model, model.isBusy {
            model.quitRequested = true
            model.showLibrary()
            return .terminateCancel
        }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { model?.floating.closeAll() }
}

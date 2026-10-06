import OpenLoomCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        @Bindable var recorder = model.recorder
        Form {
            Section("Recording defaults") {
                Picker("Codec", selection: $recorder.settings.codec) {
                    ForEach(VideoCodec.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Countdown", selection: $recorder.settings.countdownSeconds) {
                    ForEach(0...5, id: \.self) { Text($0 == 0 ? "Off" : "\($0) seconds").tag($0) }
                }
                Toggle("Record microphone", isOn: $recorder.settings.microphone)
                Toggle("Record system audio", isOn: $recorder.settings.systemAudio)
                Toggle("Include cursor", isOn: $recorder.settings.showsCursor)
            }
            .disabled(recorder.phase.isSessionActive)

            Section("Local storage") {
                Text("Recordings and exports stay in OpenLoom's private Application Support library.")
                    .foregroundStyle(.secondary)
                Button("Show library in Finder") { model.revealLibrary() }
            }
            Section("Privacy") {
                Label("App Sandbox · no network permissions", systemImage: "lock.shield")
                Text("OpenLoom does not upload, phone home, open remote links, or download models. Files copied elsewhere and system backups are controlled outside the app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: recorder.settings) { model.saveSettings() }
    }
}

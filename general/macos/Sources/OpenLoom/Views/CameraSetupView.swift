import OpenLoomCore
import SwiftUI

struct CameraSetupView: View {
    @Bindable var recorder: CaptureEngine

    var body: some View {
        @Bindable var camera = recorder.camera
        SetupSection(title: "Camera", symbol: "video") {
            HStack(spacing: 8) {
                Picker("Device", selection: Binding(get: { recorder.settings.cameraID ?? "" }, set: {
                    recorder.settings.cameraID = $0.isEmpty ? nil : $0
                    Task { await camera.stopPreview() }
                })) {
                    Text("Default camera").tag("")
                    ForEach(camera.devices) { Text($0.name).tag($0.id) }
                    if let id = recorder.settings.cameraID, !camera.devices.contains(where: { $0.id == id }) {
                        Text("Unavailable camera").tag(id)
                    }
                }.labelsHidden()
                Button("Refresh devices", systemImage: "arrow.clockwise") { camera.refreshDevices() }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
            }
            Toggle("Mirror camera", isOn: $recorder.settings.mirrorCamera)
            if recorder.settings.mode == .screenAndCamera {
                Picker("Position", selection: $recorder.settings.cameraPosition) {
                    ForEach(CameraPosition.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Bubble size", selection: $recorder.settings.cameraSize) {
                    ForEach(CameraSize.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            if let error = camera.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("The camera turns on for preview or recording.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.disabled(recorder.phase.isSessionActive || camera.isPreparing)
    }
}

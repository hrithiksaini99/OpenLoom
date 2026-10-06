import OpenLoomCore
import SwiftUI

struct CaptureOptionsView: View {
    @Bindable var recorder: CaptureEngine
    @ViewState private var advanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SetupSection(title: "Audio", symbol: "waveform") {
                Toggle("Microphone", isOn: $recorder.settings.microphone).toggleStyle(.switch)
                if recorder.settings.mode.usesScreen {
                    Toggle("System audio", isOn: $recorder.settings.systemAudio).toggleStyle(.switch)
                }
                Text(recorder.settings.microphone ? "Your default input device will be recorded." : "Microphone is off.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if recorder.settings.mode.usesCamera { CameraSetupView(recorder: recorder) }
            SetupSection(title: "Video", symbol: "slider.horizontal.3") {
                Picker("Quality", selection: $recorder.settings.resolution) {
                    ForEach(ResolutionPreset.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Frame rate", selection: $recorder.settings.framesPerSecond) {
                    ForEach([15, 30, 60], id: \.self) { Text("\($0) fps").tag($0) }
                }
                DisclosureGroup("More options", isExpanded: $advanced) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Codec", selection: $recorder.settings.codec) {
                            ForEach(VideoCodec.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        Picker("Countdown", selection: $recorder.settings.countdownSeconds) {
                            ForEach(0...5, id: \.self) { Text($0 == 0 ? "Off" : "\($0)s").tag($0) }
                        }
                        if recorder.settings.mode.usesScreen {
                            Toggle("Show cursor", isOn: $recorder.settings.showsCursor)
                            Toggle("Save click positions", isOn: $recorder.settings.captureClicks)
                            Text("Click positions support highlights and zoom for display recordings on macOS 15.2+.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.top, 10)
                }.font(.callout)
            }
        }.disabled(recorder.phase.isSessionActive)
    }
}

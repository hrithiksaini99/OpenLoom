import OpenLoomCore
import SwiftUI

struct TrimExportView: View {
    @Bindable var model: AppModel
    let recording: RecordingManifest
    @Environment(\.dismiss) private var dismiss
    @ViewState private var start: Double = 0
    @ViewState private var end: Double = 0
    @ViewState private var exporting = false
    @ViewState private var resultURL: URL?
    @ViewState private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Trim a local copy").font(.title2.bold())
            Text("Choose start and end times in seconds. Your original stays intact.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("Start", value: $start, format: .number.precision(.fractionLength(2)))
                TextField("End", value: $end, format: .number.precision(.fractionLength(2)))
            }
            .textFieldStyle(.roundedBorder).disabled(exporting || resultURL != nil)
            Text("Recording length: \(recording.duration.formatted(.number.precision(.fractionLength(2)))) seconds")
                .font(.caption).foregroundStyle(.secondary)
            if exporting {
                ProgressView(value: model.exportFraction)
                HStack {
                    Text(model.exportProgress).font(.callout)
                    Spacer()
                    Button("Cancel export") { model.cancelExport() }
                }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.callout) }
            if let resultURL {
                Label("MP4 saved to the local library", systemImage: "checkmark.circle")
                Button("Show export in Finder") { model.reveal(resultURL) }
            }
            HStack {
                Spacer()
                Button(resultURL == nil ? "Cancel" : "Done") { dismiss() }.disabled(exporting)
                if resultURL == nil {
                    Button("Export MP4") { Task { await export() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(exporting || !start.isFinite || !end.isFinite || start < 0 || end > recording.duration || end - start < 0.1)
                }
            }
        }
        .padding(28).frame(width: 480)
        .onAppear { end = recording.duration }
        .interactiveDismissDisabled(exporting)
    }

    private func export() async {
        guard !model.isExporting, !model.isRecovering, !model.recorder.phase.isSessionActive else { return }
        exporting = true
        errorMessage = nil
        defer { exporting = false }
        do {
            resultURL = try await model.exportTrim(recording, start: start, end: end)
        } catch is CancellationError { errorMessage = "Export cancelled. Your original is kept."
        } catch { errorMessage = error.localizedDescription }
    }
}

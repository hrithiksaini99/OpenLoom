import OpenLoomCore
import SwiftUI

private struct FrameRequest: Hashable {
    let time: Double
    let preview: Bool
    let revision: Int
}

struct VisualEditorView: View {
    @Bindable var model: AppModel
    let recording: RecordingManifest
    @Environment(\.dismiss) private var dismiss
    @ViewState private var edits: [VisualCue]
    @ViewState private var tool: VisualTool = .arrow
    @ViewState private var color: InkColor = .yellow
    @ViewState private var playhead: Double = 0
    @ViewState private var seconds = 3.0
    @ViewState private var zoom = 1.8
    @ViewState private var preview = false
    @ViewState private var frame: CGImage?
    @ViewState private var draft: [UnitPoint2D] = []
    @ViewState private var revision = 0
    @ViewState private var frameError: String?

    init(model: AppModel, recording: RecordingManifest) {
        self.model = model; self.recording = recording
        _edits = ViewState(wrappedValue: recording.visualEdits)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Polish your walkthrough").font(.title2.bold())
                    Text("Timed drawings, cursor highlights, and smooth zoom. Your original stays intact.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Preview edits", isOn: $preview).toggleStyle(.switch)
            }
            toolControls
            DrawingSurface(frame: frame, edits: edits, time: playhead, tool: tool, color: color, draft: $draft,
                           isPreview: preview, enabled: !preview && !model.isBusy, onComplete: appendDrawing)
                .frame(height: 310)
            HStack {
                Text(Formatters.duration(playhead)).font(.callout.monospacedDigit()).frame(width: 62)
                Slider(value: $playhead, in: 0...max(0.1, recording.duration - 0.05)).accessibilityLabel("Edit time")
                Text(Formatters.duration(recording.duration)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack {
                Text(preview ? "Preview includes active edits and zoom at this time. Switch preview off to draw." : "Drag on the frame to draw. Click to place a highlight or zoom focus.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Undo last edit", systemImage: "arrow.uturn.backward") { if !edits.isEmpty { edits.removeLast() } }
                    .disabled(edits.isEmpty || model.isBusy)
            }
            if !recording.clicks.isEmpty {
                HStack {
                    Label("\(recording.clicks.count) recorded clicks", systemImage: "cursorarrow.click").font(.caption)
                    Button("Highlight clicks") { addClickHighlights() }
                    Button("Zoom to clicks") { addClickZooms() }
                    Text("Up to 500 edits per video.").font(.caption).foregroundStyle(.secondary)
                }.disabled(model.isBusy)
            }
            editList
            if let error = frameError { Text(error).font(.caption).foregroundStyle(.red) }
            footer
        }
        .padding(24).frame(width: 920, height: 760)
        .onChange(of: edits) { revision += 1 }
        .task(id: FrameRequest(time: playhead, preview: preview, revision: revision)) {
            do {
                let url = model.library.outputURL(for: recording.id)
                try LocalFilePolicy.requireContained(url, in: model.library.root)
                let result = try await model.exporter.preview(input: url, time: playhead, edits: preview ? edits : [], settings: recording.settings)
                try Task.checkCancellation()
                frame = result; frameError = nil
            } catch is CancellationError {
            } catch { if !Task.isCancelled { frameError = error.localizedDescription } }
        }
        .interactiveDismissDisabled(model.isExporting)
    }

    private var toolControls: some View {
        HStack(spacing: 16) {
            Picker("Tool", selection: $tool) {
                ForEach(VisualTool.allCases, id: \.self) { Label($0.label, systemImage: $0.symbol).tag($0) }
            }.pickerStyle(.segmented).frame(maxWidth: 480)
            Picker("Ink", selection: $color) {
                ForEach(InkColor.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }.frame(width: 120).disabled(tool == .zoom)
            if tool == .zoom {
                Picker("Zoom", selection: $zoom) {
                    ForEach([1.4, 1.8, 2.2, 2.6], id: \.self) { Text("\($0, specifier: "%.1f")×").tag($0) }
                }.frame(width: 100)
            }
            Picker("Duration", selection: $seconds) {
                ForEach([1.0, 3, 5, 10], id: \.self) { Text("\(Int($0))s").tag($0) }
            }.frame(width: 110)
        }.disabled(model.isBusy)
    }

    private var editList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if edits.isEmpty { Text("No visual edits yet.").foregroundStyle(.secondary).padding(8) }
                ForEach(edits) { cue in
                    HStack {
                        Label(cue.tool.label, systemImage: cue.tool.symbol).frame(width: 120, alignment: .leading)
                        Button("\(Formatters.duration(cue.start)) – \(Formatters.duration(cue.end))") { playhead = cue.start + min(0.4, (cue.end - cue.start) / 2) }
                            .buttonStyle(.borderless).font(.caption.monospacedDigit())
                        if cue.tool == .zoom { Text("\(cue.zoom, specifier: "%.1f")×").font(.caption) }
                        Spacer()
                        Button("Remove edit", systemImage: "trash") { edits.removeAll { $0.id == cue.id } }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).disabled(model.isBusy)
                    }.padding(.horizontal, 8).padding(.vertical, 4)
                }
            }
        }.frame(height: 115).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
    }

    private var footer: some View {
        HStack {
            if model.isExporting {
                ProgressView(value: model.exportFraction).frame(width: 110)
                Text(model.exportFraction.map { "Rendering · \(Int($0 * 100))%" } ?? "Preparing export…").font(.callout)
                Button("Cancel export") { model.cancelExport() }
            } else { Text("\(edits.count) / 500 edits · local only").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }.disabled(model.isExporting)
            Button("Save edits") {
                do { try model.saveEdits(for: recording.id, edits: edits); dismiss() }
                catch { model.errorMessage = error.localizedDescription }
            }.disabled(model.isBusy)
            Button("Export polished MP4", systemImage: "square.and.arrow.down") {
                Task { await model.exportPolished(recording, edits: edits) }
            }.buttonStyle(.borderedProminent).disabled(edits.isEmpty || model.isBusy)
        }
    }

    private func appendDrawing() {
        guard !draft.isEmpty, edits.count < 500, recording.duration >= 0.1 else { draft = []; return }
        let start = min(playhead, recording.duration - 0.1)
        let points: [UnitPoint2D]
        switch tool {
        case .pen: points = draft
        case .arrow, .rectangle: points = [draft[0], draft[draft.count - 1]]
        case .highlight, .zoom: points = [draft[0]]
        }
        edits.append(VisualCue(start: start, end: min(recording.duration, start + seconds), tool: tool, points: points, color: color, zoom: zoom))
        draft = []
    }
    private func addClickHighlights() {
        let ids = Set(edits.map(\.id))
        let available = recording.clicks.filter { !ids.contains($0.id) }.compactMap { $0.highlight(duration: recording.duration) }
        edits.append(contentsOf: available.prefix(max(0, 500 - edits.count)))
    }
    private func addClickZooms() {
        var last = -10.0
        for click in recording.clicks.sorted(by: { $0.time < $1.time }) where click.time - last >= 2.5 && edits.count < 500 {
            let start = max(0, click.time - 0.3), end = min(recording.duration, click.time + 2)
            guard end > start, !edits.contains(where: { $0.tool == .zoom && $0.start < end && start < $0.end }) else { continue }
            edits.append(VisualCue(start: start, end: end, tool: .zoom, points: [click.point], zoom: zoom))
            last = click.time
        }
    }
}

private struct DrawingSurface: View {
    let frame: CGImage?
    let edits: [VisualCue]
    let time: Double
    let tool: VisualTool
    let color: InkColor
    @Binding var draft: [UnitPoint2D]
    let isPreview: Bool
    let enabled: Bool
    let onComplete: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let ratio = frame.map { Double($0.width) / Double($0.height) } ?? 16 / 9
            let width = min(proxy.size.width, proxy.size.height * ratio)
            let height = width / ratio
            ZStack {
                if let frame { Image(decorative: frame, scale: 1).resizable().frame(width: width, height: height) }
                else { ProgressView().frame(width: width, height: height) }
                if !isPreview {
                    Canvas { context, size in
                        for cue in edits where cue.start <= time && time < cue.end {
                            paint(cue.tool, points: cue.points, ink: cue.color, in: &context, size: size)
                        }
                        paint(tool, points: draft, ink: color, in: &context, size: size)
                    }.frame(width: width, height: height).allowsHitTesting(false)
                }
            }
            .frame(width: width, height: height).background(.black)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard enabled, frame != nil else { return }
                    func unit(_ p: CGPoint) -> UnitPoint2D { UnitPoint2D(x: min(1, max(0, p.x / width)), y: min(1, max(0, p.y / height))) }
                    if draft.isEmpty { draft = [unit(value.startLocation)] }
                    let p = unit(value.location)
                    if tool == .pen, draft.count < 2_000 {
                        if let last = draft.last, abs(p.x - last.x) + abs(p.y - last.y) > 0.002 { draft.append(p) }
                    } else if draft.count == 1 { draft.append(p) }
                    else { draft[draft.count - 1] = p }
                }
                .onEnded { _ in if enabled { onComplete() } else { draft = [] } })
            .accessibilityLabel("Video frame. Drag to draw or click to place an effect.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func paint(_ tool: VisualTool, points: [UnitPoint2D], ink: InkColor, in context: inout GraphicsContext, size: CGSize) {
        guard let first = points.first else { return }
        func p(_ point: UnitPoint2D) -> CGPoint { CGPoint(x: point.x * size.width, y: point.y * size.height) }
        let color: Color = switch ink { case .yellow: .yellow; case .red: .red; case .blue: .blue; case .green: .green }
        var path = Path()
        switch tool {
        case .pen: path.move(to: p(first)); for point in points.dropFirst() { path.addLine(to: p(point)) }
        case .arrow:
            guard let last = points.last else { return }
            let a = p(first), b = p(last), angle = atan2(b.y - a.y, b.x - a.x)
            path.move(to: a); path.addLine(to: b)
            path.move(to: b); path.addLine(to: CGPoint(x: b.x - 14 * cos(angle - .pi / 6), y: b.y - 14 * sin(angle - .pi / 6)))
            path.move(to: b); path.addLine(to: CGPoint(x: b.x - 14 * cos(angle + .pi / 6), y: b.y - 14 * sin(angle + .pi / 6)))
        case .rectangle:
            guard let last = points.last else { return }
            let a = p(first), b = p(last)
            path.addRect(CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)))
        case .highlight, .zoom:
            let center = p(first), radius: Double = tool == .zoom ? 12 : max(10, size.height * 0.035)
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            if tool == .highlight { context.fill(path, with: .color(color.opacity(0.28))) }
        }
        context.stroke(path, with: .color(tool == .zoom ? .white : color), style: StrokeStyle(lineWidth: max(2, size.height * 0.006), lineCap: .round, lineJoin: .round))
    }
}

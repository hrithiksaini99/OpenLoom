import OpenLoomCore
import SwiftUI

struct LibrarySidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                OpenLoomMark(size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("OpenLoom").font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("Your local studio").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 18)

            Button { model.selectedID = nil } label: {
                Label("New recording", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered).controlSize(.large)
            .padding(.horizontal, 14).padding(.bottom, 12)
            .help("New recording (⌘N)")

            List(selection: $model.selectedID) {
                Section {
                    ForEach(model.filteredRecordings) { recording in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: recording.status == .ready ? "play.rectangle" : "exclamationmark.circle")
                                .foregroundStyle(recording.status == .ready ? Color.secondary : .orange)
                                .padding(.top, 3)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(recording.title).font(.subheadline.weight(.medium)).lineLimit(2)
                                Text(subtitle(recording)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .padding(.vertical, 6)
                        .tag(recording.id)
                        .contextMenu {
                            Button("Show files in Finder") { model.reveal(model.library.folder(for: recording.id)) }
                        }
                    }
                } header: {
                    HStack {
                        Text("Library")
                        Spacer()
                        Text("\(model.filteredRecordings.count)").monospacedDigit()
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $model.search, placement: .sidebar, prompt: "Search recordings")
            .overlay {
                if model.filteredRecordings.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: model.search.isEmpty ? "tray" : "magnifyingglass").font(.title2)
                        Text(model.search.isEmpty ? "Your recordings will appear here." : "No recordings match.")
                            .font(.callout).multilineTextAlignment(.center)
                    }.foregroundStyle(.secondary).padding(24).allowsHitTesting(false)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Label("Saved on this Mac", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
                Button("Open library folder", systemImage: "folder") { model.revealLibrary() }
                    .buttonStyle(.plain).font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }
    }

    private func subtitle(_ recording: RecordingManifest) -> String {
        if recording.status == .ready {
            return "\(Formatters.duration(recording.duration)) · \(recording.createdAt.formatted(date: .abbreviated, time: .omitted))"
        }
        return model.recorder.manifest?.id == recording.id ? model.recorder.phase.label : "Needs recovery · sources kept"
    }
}

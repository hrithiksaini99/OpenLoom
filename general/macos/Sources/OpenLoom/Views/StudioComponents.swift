import OpenLoomCore
import SwiftUI

struct LocalStorageBadge: View {
    var body: some View {
        Label("Local only", systemImage: "lock.shield")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.green.opacity(0.07), in: .capsule)
            .help("Recordings and exports stay on this Mac. OpenLoom has no network permission.")
    }
}

struct SetupSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.quaternary, lineWidth: 1))
    }
}

extension CaptureMode {
    var symbol: String {
        switch self {
        case .screen: "display"
        case .screenAndCamera: "person.crop.rectangle"
        case .camera: "video"
        }
    }
    var hint: String {
        switch self {
        case .screen: "Display or window"
        case .screenAndCamera: "With a camera bubble"
        case .camera: "Webcam recording"
        }
    }
}

struct CaptureModeSelector: View {
    @Binding var selection: CaptureMode

    var body: some View {
        HStack(spacing: 10) {
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                Button { selection = mode } label: {
                    HStack(spacing: 10) {
                        Image(systemName: mode.symbol).font(.title3)
                            .foregroundStyle(selection == mode ? StudioStyle.violet : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.label).font(.subheadline.weight(.semibold))
                            Text(mode.hint).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(selection == mode ? StudioStyle.violet.opacity(0.1) : Color(nsColor: .controlBackgroundColor),
                                in: .rect(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(selection == mode ? StudioStyle.violet.opacity(0.6) : Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1))
                    .contentShape(.rect(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == mode ? [.isSelected] : [])
            }
        }
    }
}

import SwiftUI

enum StudioStyle {
    static let coral = Color(red: 0.93, green: 0.37, blue: 0.32)
    // White labels need at least 4.5:1 contrast; the lighter brand coral is decorative.
    static let recordingAction = Color(red: 198.0 / 255, green: 61.0 / 255, blue: 50.0 / 255)
    static let violet = Color(red: 0.48, green: 0.34, blue: 0.88)
    static let gradient = LinearGradient(colors: [coral, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Original ribbon mark, drawn as a vector at every size.
struct OpenLoomMark: View {
    var size: CGFloat = 40
    var active = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(StudioStyle.gradient)
            RibbonShape().stroke(.white, style: StrokeStyle(lineWidth: size * 0.078, lineCap: .round, lineJoin: .round))
                .padding(size * 0.18)
            if active {
                Circle().fill(.white).frame(width: size * 0.13, height: size * 0.13)
                    .offset(x: size * 0.24, y: size * 0.24)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

private struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { .init(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        var path = Path()
        path.move(to: point(0.1, 0.52))
        path.addCurve(to: point(0.53, 0.39), control1: point(0.08, 0.1), control2: point(0.38, 0.06))
        path.addCurve(to: point(0.9, 0.48), control1: point(0.78, 0.88), control2: point(0.94, 0.88))
        path.addCurve(to: point(0.47, 0.61), control1: point(0.92, 0.1), control2: point(0.63, 0.08))
        path.addCurve(to: point(0.1, 0.52), control1: point(0.22, 0.92), control2: point(0.06, 0.88))
        return path
    }
}

struct FloatingGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content.background(.regularMaterial, in: .capsule)
                .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
        }
    }
}

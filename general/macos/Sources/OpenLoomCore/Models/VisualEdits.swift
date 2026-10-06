import Foundation

/// Points use a top-left origin and stay independent of recording resolution.
public struct UnitPoint2D: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public var isValid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
}

public enum VisualTool: String, Codable, CaseIterable, Sendable {
    case pen, arrow, rectangle, highlight, zoom
    public var label: String { rawValue.capitalized }
    public var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .highlight: "cursorarrow.rays"
        case .zoom: "plus.magnifyingglass"
        }
    }
}

public enum InkColor: String, Codable, CaseIterable, Sendable {
    case yellow, red, blue, green
}

public struct VisualCue: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var start: Double
    public var end: Double
    public var tool: VisualTool
    public var points: [UnitPoint2D]
    public var color: InkColor
    public var zoom: Double
    public init(id: UUID = UUID(), start: Double, end: Double, tool: VisualTool,
                points: [UnitPoint2D], color: InkColor = .yellow, zoom: Double = 1.8) {
        self.id = id; self.start = start; self.end = end; self.tool = tool
        self.points = points; self.color = color; self.zoom = zoom
    }
    public func validate() throws {
        guard start.isFinite, end.isFinite, start >= 0, end > start, end <= 86_400,
              (1...2_000).contains(points.count), points.allSatisfy(\.isValid),
              zoom.isFinite, (1...3).contains(zoom),
              ![VisualTool.arrow, .rectangle].contains(tool) || points.count >= 2 else {
            throw OpenLoomError.invalidReview
        }
    }
    public func zoomFactor(at time: Double) -> Double {
        guard tool == .zoom, start <= time, time < end else { return 1 }
        let ramp = min(0.35, (end - start) / 3)
        let t = min(1, max(0, min(time - start, end - time) / ramp))
        let eased = t * t * (3 - 2 * t)
        return 1 + (zoom - 1) * eased
    }
}

public struct CursorClick: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let time: Double
    public let point: UnitPoint2D
    public init(time: Double, point: UnitPoint2D) { id = UUID(); self.time = time; self.point = point }
    public func validate() throws {
        guard time.isFinite, (0...86_400).contains(time), point.isValid else { throw OpenLoomError.invalidReview }
    }
    public func highlight(duration: Double) -> VisualCue? {
        let end = min(time + 0.8, duration)
        guard end > time else { return nil }
        return VisualCue(id: id, start: time, end: end, tool: .highlight, points: [point])
    }
}

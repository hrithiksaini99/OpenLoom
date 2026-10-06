import Foundation

public enum ResolutionPreset: String, CaseIterable, Codable, Sendable {
    case hd720, hd1080, uhd4K

    public var label: String {
        switch self {
        case .hd720: "720p"
        case .hd1080: "1080p"
        case .uhd4K: "4K"
        }
    }

    public var maximumSize: (width: Int, height: Int) {
        switch self {
        case .hd720: (1280, 720)
        case .hd1080: (1920, 1080)
        case .uhd4K: (3840, 2160)
        }
    }
}

public enum VideoCodec: String, CaseIterable, Codable, Sendable {
    case h264, hevc
    public var label: String { self == .h264 ? "H.264 · compatible" : "HEVC · smaller files" }
}

public enum CaptureMode: String, CaseIterable, Codable, Sendable {
    case screen, screenAndCamera, camera
    public var label: String {
        switch self {
        case .screen: "Screen"
        case .screenAndCamera: "Screen + camera"
        case .camera: "Camera only"
        }
    }
    public var usesScreen: Bool { self != .camera }
    public var usesCamera: Bool { self != .screen }
}

public enum CameraPosition: String, CaseIterable, Codable, Sendable {
    case bottomRight, bottomLeft, topRight, topLeft
    public var label: String {
        switch self {
        case .bottomRight: "Bottom right"
        case .bottomLeft: "Bottom left"
        case .topRight: "Top right"
        case .topLeft: "Top left"
        }
    }
}

public enum CameraSize: String, CaseIterable, Codable, Sendable {
    case small, medium, large
    public var label: String { rawValue.capitalized }
    public var fraction: Double {
        switch self { case .small: 0.18; case .medium: 0.25; case .large: 0.33 }
    }
}

public struct RecordingSettings: Codable, Equatable, Sendable {
    public var resolution: ResolutionPreset = .hd1080
    public var framesPerSecond: Int = 30
    public var codec: VideoCodec = .h264
    public var systemAudio: Bool = true
    public var microphone: Bool = false
    public var showsCursor: Bool = true
    public var countdownSeconds: Int = 3
    public var mode: CaptureMode = .screen
    public var cameraID: String?
    public var cameraPosition: CameraPosition = .bottomRight
    public var cameraSize: CameraSize = .medium
    public var mirrorCamera: Bool = true
    public var captureClicks: Bool = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case resolution, framesPerSecond, codec, systemAudio, microphone, showsCursor, countdownSeconds
        case mode, cameraID, cameraPosition, cameraSize, mirrorCamera, captureClicks
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        resolution = try c.decodeIfPresent(ResolutionPreset.self, forKey: .resolution) ?? .hd1080
        framesPerSecond = try c.decodeIfPresent(Int.self, forKey: .framesPerSecond) ?? 30
        codec = try c.decodeIfPresent(VideoCodec.self, forKey: .codec) ?? .h264
        systemAudio = try c.decodeIfPresent(Bool.self, forKey: .systemAudio) ?? true
        microphone = try c.decodeIfPresent(Bool.self, forKey: .microphone) ?? false
        showsCursor = try c.decodeIfPresent(Bool.self, forKey: .showsCursor) ?? true
        countdownSeconds = try c.decodeIfPresent(Int.self, forKey: .countdownSeconds) ?? 3
        mode = try c.decodeIfPresent(CaptureMode.self, forKey: .mode) ?? .screen
        cameraID = try c.decodeIfPresent(String.self, forKey: .cameraID)
        cameraPosition = try c.decodeIfPresent(CameraPosition.self, forKey: .cameraPosition) ?? .bottomRight
        cameraSize = try c.decodeIfPresent(CameraSize.self, forKey: .cameraSize) ?? .medium
        mirrorCamera = try c.decodeIfPresent(Bool.self, forKey: .mirrorCamera) ?? true
        captureClicks = try c.decodeIfPresent(Bool.self, forKey: .captureClicks) ?? false
    }

    public func validate() throws {
        guard [15, 30, 60].contains(framesPerSecond), (0...5).contains(countdownSeconds),
              (cameraID?.count ?? 0) <= 500 else {
            throw OpenLoomError.invalidSettings
        }
    }
}

public struct CaptureDimensions: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public static func fit(width: Double, height: Double, preset: ResolutionPreset) throws -> Self {
        guard width.isFinite, height.isFinite, width >= 2, height >= 2 else {
            throw OpenLoomError.invalidDimensions
        }
        let cap = preset.maximumSize
        let scale = min(1, Double(cap.width) / width, Double(cap.height) / height)
        return Self(width: max(2, Int(width * scale) / 2 * 2), height: max(2, Int(height * scale) / 2 * 2))
    }
}

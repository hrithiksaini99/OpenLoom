@preconcurrency import AVFoundation
import CoreImage
import Foundation

final class VideoRenderInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = true
    let containsTweening = true
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let requiredSourceTrackIDs: [NSValue]?
    let mainTrackID: CMPersistentTrackID
    let cameraTrackID: CMPersistentTrackID?
    let mainTransform: CGAffineTransform
    let cameraTransform: CGAffineTransform
    let settings: RecordingSettings
    let edits: [VisualCue]

    init(duration: CMTime, mainTrackID: CMPersistentTrackID, cameraTrackID: CMPersistentTrackID? = nil,
         mainTransform: CGAffineTransform, cameraTransform: CGAffineTransform = .identity,
         settings: RecordingSettings, edits: [VisualCue] = []) {
        timeRange = CMTimeRange(start: .zero, duration: duration)
        self.mainTrackID = mainTrackID; self.cameraTrackID = cameraTrackID
        self.mainTransform = mainTransform; self.cameraTransform = cameraTransform
        self.settings = settings; self.edits = edits
        requiredSourceTrackIDs = ([mainTrackID] + (cameraTrackID.map { [$0] } ?? [])).map { NSNumber(value: $0) }
    }
}

/// AVFoundation calls this from export workers. Frame rendering stays off the main actor.
final class NativeVideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.openloom.video-compositor", qos: .userInitiated)
    private let renderer = VideoFrameRenderer()
    private var context: AVVideoCompositionRenderContext?
    private var generation = 0
    private let cancellationLock = NSLock()
    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]]
    }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferIOSurfacePropertiesKey as String: [String: Int]()]
    }
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        queue.sync { context = newRenderContext }
    }
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        let token = cancellationLock.withLock { generation }
        queue.async {
            guard self.cancellationLock.withLock({ self.generation == token }) else { request.finishCancelledRequest(); return }
            guard let instruction = request.videoCompositionInstruction as? VideoRenderInstruction,
                  let source = request.sourceFrame(byTrackID: instruction.mainTrackID),
                  let context = self.context, let target = context.newPixelBuffer() else {
                request.finish(with: OpenLoomError.exportUnavailable); return
            }
            let camera = instruction.cameraTrackID.flatMap { request.sourceFrame(byTrackID: $0) }.map { CIImage(cvPixelBuffer: $0) }
            let bounds = CGRect(origin: .zero, size: context.size)
            let image = self.renderer.render(base: CIImage(cvPixelBuffer: source), camera: camera,
                                             mainTransform: instruction.mainTransform, cameraTransform: instruction.cameraTransform,
                                             settings: instruction.settings, edits: instruction.edits,
                                             time: request.compositionTime.seconds, bounds: bounds)
            self.renderer.context.render(image, to: target, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
            request.finish(withComposedVideoFrame: target)
        }
    }
    func cancelAllPendingVideoCompositionRequests() {
        cancellationLock.withLock { generation += 1 }
    }
}

/// Shared by export and the editor's still-frame preview. CIContext uses Metal when available.
final class VideoFrameRenderer {
    let context = CIContext(options: [.cacheIntermediates: false])
    private var overlayCache: [UUID: (image: CIImage, cost: Int)] = [:]
    private var cacheOrder: [UUID] = []
    private var cacheBytes = 0
    private let cacheLimit = 24 * 1_024 * 1_024

    func render(base: CIImage, camera: CIImage? = nil, mainTransform: CGAffineTransform = .identity,
                cameraTransform: CGAffineTransform = .identity, settings: RecordingSettings,
                edits: [VisualCue], time: Double, bounds: CGRect) -> CIImage {
        var image = oriented(base, transform: mainTransform)
        image = image.transformed(by: CGAffineTransform(scaleX: bounds.width / image.extent.width, y: bounds.height / image.extent.height))
        for cue in edits where cue.start <= time && time < cue.end && cue.tool != .zoom {
            if let overlay = overlayCache[cue.id]?.image ?? draw(cue: cue, bounds: bounds) {
                cache(overlay, for: cue.id)
                image = overlay.composited(over: image)
            }
        }
        if let cue = edits.last(where: { $0.tool == .zoom && $0.start <= time && time < $0.end }), let focus = cue.points.first {
            let scale = cue.zoomFactor(at: time)
            let x = min(0, max(bounds.width * (1 - scale), bounds.width / 2 - focus.x * bounds.width * scale))
            let y = min(0, max(bounds.height * (1 - scale), bounds.height / 2 - (1 - focus.y) * bounds.height * scale))
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: x, y: y)))
        }
        image = image.cropped(to: bounds)
        if let camera {
            let diameter = min(bounds.width * settings.cameraSize.fraction, bounds.height * 0.48)
            let margin = max(8, bounds.height * 0.035)
            let left = settings.cameraPosition == .bottomLeft || settings.cameraPosition == .topLeft
            let top = settings.cameraPosition == .topLeft || settings.cameraPosition == .topRight
            let rect = CGRect(x: left ? margin : bounds.width - margin - diameter,
                              y: top ? bounds.height - margin - diameter : margin,
                              width: diameter, height: diameter)
            var inset = oriented(camera, transform: cameraTransform)
            let scale = max(diameter / inset.extent.width, diameter / inset.extent.height)
            inset = inset.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            inset = inset.transformed(by: CGAffineTransform(translationX: rect.midX - inset.extent.midX, y: rect.midY - inset.extent.midY))
            if let mask = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: rect.midX, y: rect.midY), "inputRadius0": diameter / 2 - 1,
                "inputRadius1": diameter / 2, "inputColor0": CIColor.white, "inputColor1": CIColor.black,
            ])?.outputImage?.cropped(to: bounds) {
                image = inset.cropped(to: rect).applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask])
            }
        }
        return image.cropped(to: bounds)
    }

    private func oriented(_ image: CIImage, transform: CGAffineTransform) -> CIImage {
        let result = image.transformed(by: transform)
        return result.transformed(by: CGAffineTransform(translationX: -result.extent.minX, y: -result.extent.minY))
    }

    private func draw(cue: VisualCue, bounds: CGRect) -> CIImage? {
        guard let first = cue.points.first else { return nil }
        let xs = cue.points.map { $0.x * bounds.width }, ys = cue.points.map { (1 - $0.y) * bounds.height }
        let margin = max(16, bounds.height * 0.05)
        let tile = CGRect(x: (xs.min() ?? 0) - margin, y: (ys.min() ?? 0) - margin,
                          width: (xs.max() ?? 0) - (xs.min() ?? 0) + margin * 2,
                          height: (ys.max() ?? 0) - (ys.min() ?? 0) + margin * 2).integral.intersection(bounds)
        guard tile.width > 0, tile.height > 0,
              let context = CGContext(data: nil, width: Int(tile.width), height: Int(tile.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: -tile.minX, y: -tile.minY)
        func point(_ p: UnitPoint2D) -> CGPoint { CGPoint(x: p.x * bounds.width, y: (1 - p.y) * bounds.height) }
        let color: CGColor = switch cue.color {
        case .yellow: CGColor(red: 1, green: 0.82, blue: 0.05, alpha: 1)
        case .red: CGColor(red: 1, green: 0.2, blue: 0.22, alpha: 1)
        case .blue: CGColor(red: 0.12, green: 0.56, blue: 1, alpha: 1)
        case .green: CGColor(red: 0.15, green: 0.85, blue: 0.35, alpha: 1)
        }
        context.setStrokeColor(color); context.setFillColor(color)
        context.setLineWidth(max(3, bounds.height * 0.006))
        context.setLineCap(.round); context.setLineJoin(.round)
        switch cue.tool {
        case .pen:
            context.move(to: point(first))
            for p in cue.points.dropFirst() { context.addLine(to: point(p)) }
            if cue.points.count == 1 { context.addLine(to: point(first)) }
            context.strokePath()
        case .arrow:
            guard let last = cue.points.last else { return nil }
            let a = point(first), b = point(last)
            context.move(to: a); context.addLine(to: b); context.strokePath()
            let angle = atan2(b.y - a.y, b.x - a.x)
            let size = max(12, bounds.height * 0.025)
            context.move(to: b)
            context.addLine(to: CGPoint(x: b.x - size * cos(angle - .pi / 6), y: b.y - size * sin(angle - .pi / 6)))
            context.move(to: b)
            context.addLine(to: CGPoint(x: b.x - size * cos(angle + .pi / 6), y: b.y - size * sin(angle + .pi / 6)))
            context.strokePath()
        case .rectangle:
            guard let last = cue.points.last else { return nil }
            let a = point(first), b = point(last)
            context.stroke(CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)))
        case .highlight:
            let center = point(first), radius = max(10, bounds.height * 0.035)
            let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.setAlpha(0.28); context.fillEllipse(in: circle)
            context.setAlpha(0.95); context.strokeEllipse(in: circle)
        case .zoom: break
        }
        guard let image = context.makeImage() else { return nil }
        return CIImage(cgImage: image).transformed(by: CGAffineTransform(translationX: tile.minX, y: tile.minY))
    }

    private func cache(_ image: CIImage, for id: UUID) {
        if overlayCache[id] != nil { cacheOrder.removeAll { $0 == id }; cacheOrder.append(id); return }
        let cost = Int(image.extent.width * image.extent.height) * 4
        guard cost <= cacheLimit else { return }
        while cacheBytes + cost > cacheLimit, let oldest = cacheOrder.first {
            cacheOrder.removeFirst()
            if let removed = overlayCache.removeValue(forKey: oldest) { cacheBytes -= removed.cost }
        }
        overlayCache[id] = (image, cost); cacheOrder.append(id); cacheBytes += cost
    }
}

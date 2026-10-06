@preconcurrency import AVFoundation
import CoreImage
import Foundation

/// Preview views receive small images, never a capture session or its locking preview layer.
final class CameraPreviewFrames: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (CGImage) -> Void)?
    private var enabled = false
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var lastFrame = -Double.infinity // Used only by the serial preview sample queue.

    func setHandler(_ handler: @escaping @Sendable (CGImage) -> Void) { lock.withLock { self.handler = handler } }
    func setEnabled(_ enabled: Bool) { lock.withLock { self.enabled = enabled } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let handler = lock.withLock { enabled ? handler : nil }
        guard let handler, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFrame >= 0.1 else { return }
        lastFrame = now
        let source = CIImage(cvPixelBuffer: buffer)
        let scale = min(1, 720 / source.extent.width, 450 / source.extent.height)
        let image = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let frame = context.createCGImage(image, from: image.extent) else { return }
        handler(frame)
    }
}

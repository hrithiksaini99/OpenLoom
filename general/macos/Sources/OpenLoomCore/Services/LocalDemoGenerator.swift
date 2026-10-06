@preconcurrency import AVFoundation
import CoreText
import Foundation

/// A device-free demo for exploring review tools. It contains no recorded screen, camera, or audio.
public actor LocalDemoGenerator {
    public init() {}
    public func write(to url: URL) async throws {
        try LocalFilePolicy.requireLocalFile(url)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw OpenLoomError.unsafePath }
        let width = 960, height = 540, fps = 30, seconds = 6
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_000_000],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Int](),
        ])
        guard writer.canAdd(input) else { throw OpenLoomError.exportUnavailable }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? OpenLoomError.exportUnavailable }
        writer.startSession(atSourceTime: .zero)
        var complete = false
        defer { if !complete { writer.cancelWriting() } }
        let font = CTFontCreateWithName("HelveticaNeue" as CFString, 24, nil)
        for frame in 0..<(seconds * fps) {
            try Task.checkCancellation()
            var waited = 0
            while !input.isReadyForMoreMediaData {
                guard writer.status != .failed, waited < 10_000 else { throw writer.error ?? OpenLoomError.exportUnavailable }
                try await Task.sleep(for: .milliseconds(1)); waited += 1
            }
            var pixel: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool,
                  CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixel) == kCVReturnSuccess,
                  let pixel else { throw OpenLoomError.exportUnavailable }
            CVPixelBufferLockBaseAddress(pixel, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: width, height: height,
                                       bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel),
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) {
                paint(context, time: Double(frame) / Double(fps), width: width, height: height, font: font)
            }
            CVPixelBufferUnlockBaseAddress(pixel, [])
            guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: CMTimeScale(fps))) else {
                throw writer.error ?? OpenLoomError.exportUnavailable
            }
        }
        writer.endSession(atSourceTime: CMTime(value: Int64(seconds), timescale: 1))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? OpenLoomError.exportUnavailable }
        complete = true
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func paint(_ context: CGContext, time: Double, width: Int, height: Int, font: CTFont) {
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(red: 0.08, green: 0.10, blue: 0.15, alpha: 1)); context.fill(bounds)
        context.setFillColor(CGColor(red: 0.15, green: 0.18, blue: 0.25, alpha: 1))
        context.fill(CGRect(x: 44, y: 82, width: 872, height: 340))
        func text(_ value: String, x: Double, y: Double, small: Bool = false) {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): small ? CTFontCreateCopyWithAttributes(font, 17, nil, nil) : font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.95, alpha: 1),
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
            context.textPosition = CGPoint(x: x, y: y); CTLineDraw(line, context)
        }
        text("OpenLoom · a local walkthrough", x: 48, y: 466)
        text("Generated demo · no devices or audio", x: 48, y: 38, small: true)
        let step = min(2, Int(time / 2))
        let titles = ["1. Record a walkthrough", "2. Find a key moment", "3. Draw, highlight, and zoom"]
        text(titles[step], x: 74, y: 365)
        let subtitles = ["Screen, camera, microphone — saved on this Mac", "Search captions or jump to a chapter", "Export a new MP4 and keep your original"]
        text(subtitles[step], x: 74, y: 325, small: true)
        context.setLineWidth(4)
        context.setStrokeColor(CGColor(red: 0.28, green: 0.68, blue: 1, alpha: 1))
        context.move(to: CGPoint(x: 100, y: 170))
        for index in 0...12 {
            let x = 100 + Double(index) * 57
            let y = 170 + Double(index) * 5 + sin(Double(index) * 0.8 + time * 0.2) * 20
            context.addLine(to: CGPoint(x: x, y: y))
        }
        context.strokePath()
        for index in 0..<3 {
            context.setFillColor(CGColor(red: index == step ? 0.28 : 0.27, green: index == step ? 0.68 : 0.30,
                                         blue: index == step ? 1 : 0.36, alpha: 1))
            context.fillEllipse(in: CGRect(x: 812 + index * 24, y: 38, width: 10, height: 10))
        }
    }
}

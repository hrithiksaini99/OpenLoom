@preconcurrency import AVFoundation
import Foundation

enum SyntheticMedia {
    /// Generate colored video and independent sine-wave audio tracks; never reads a device or screen.
    static func write(to url: URL, blue: Bool = false, audioTracks: Int = 1,
                      bluePatch: Bool = false, fileType: AVFileType = .mp4) async throws {
        // Short segments avoid fixture-side encoder backpressure between independent tracks.
        let seconds = 1
        let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 160,
            AVVideoHeightKey: 90,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 250_000],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 160,
            kCVPixelBufferHeightKey as String: 90,
        ])
        guard writer.canAdd(video) else { throw FixtureError.writer }
        writer.add(video)
        var audio: [AVAssetWriterInput] = []
        let format = try audioFormat()
        for index in 0..<audioTracks {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
            ], sourceFormatHint: format)
            guard writer.canAdd(input) else { throw FixtureError.audioTrack(index) }
            writer.add(input)
            audio.append(input)
        }
        guard writer.startWriting() else { throw writer.error ?? FixtureError.writer }
        writer.startSession(atSourceTime: .zero)
        var audioPositions = Array(repeating: 0, count: audioTracks)
        for frame in 0..<(seconds * 30) {
            try await waitUntilReady(video, writer: writer)
            var pixel: CVPixelBuffer?
            let code = CVPixelBufferCreate(kCFAllocatorDefault, 160, 90, kCVPixelFormatType_32BGRA, nil, &pixel)
            guard code == kCVReturnSuccess, let pixel else { throw FixtureError.buffer }
            CVPixelBufferLockBaseAddress(pixel, [])
            if let base = CVPixelBufferGetBaseAddress(pixel) {
                let stride = CVPixelBufferGetBytesPerRow(pixel)
                let bytes = base.assumingMemoryBound(to: UInt8.self)
                for y in 0..<90 {
                    for x in 0..<160 {
                        let offset = y * stride + x * 4
                        let isBlue = blue || (bluePatch && x < 64 && y < 36)
                        bytes[offset] = isBlue ? 240 : 16
                        bytes[offset + 1] = 16
                        bytes[offset + 2] = isBlue ? 16 : 240
                        bytes[offset + 3] = 255
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pixel, [])
            guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
                throw writer.error ?? FixtureError.writer
            }
            let boundary = min(seconds * 48_000, (frame + 1) * 1600)
            for track in audio.indices {
                while audioPositions[track] < boundary {
                    try await waitUntilReady(audio[track], writer: writer)
                    let count = min(1024, seconds * 48_000 - audioPositions[track])
                    let sample = try audioSample(position: audioPositions[track], count: count, frequency: track == 0 ? 440 : 880, format: format)
                    guard audio[track].append(sample) else { throw writer.error ?? FixtureError.writer }
                    audioPositions[track] += count
                }
            }
        }
        writer.endSession(atSourceTime: CMTime(value: Int64(seconds), timescale: 1))
        video.markAsFinished()
        for input in audio { input.markAsFinished() }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? FixtureError.writer }
    }

    private static func waitUntilReady(_ input: AVAssetWriterInput, writer: AVAssetWriter) async throws {
        for _ in 0..<10_000 {
            if input.isReadyForMoreMediaData { return }
            if writer.status == .failed { throw writer.error ?? FixtureError.writer }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw FixtureError.writer
    }

    private static func audioFormat() throws -> CMAudioFormatDescription {
        var description = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
                                                       mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                                       mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                                                       mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description,
                                            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
                                            extensions: nil, formatDescriptionOut: &format) == noErr, let format else { throw FixtureError.buffer }
        return format
    }

    private static func audioSample(position: Int, count: Int, frequency: Double, format: CMAudioFormatDescription) throws -> CMSampleBuffer {
        let floats = (0..<count).map { Float(sin(2 * .pi * frequency * Double(position + $0) / 48_000) * 0.2) }
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                                                blockLength: count * 4, blockAllocator: kCFAllocatorDefault,
                                                customBlockSource: nil, offsetToData: 0, dataLength: count * 4,
                                                flags: 0, blockBufferOut: &block) == noErr, let block else { throw FixtureError.buffer }
        let result = floats.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: count * 4)
        }
        guard result == noErr else { throw FixtureError.buffer }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
                                        presentationTimeStamp: CMTime(value: Int64(position), timescale: 48_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                                        sampleCount: count, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                        sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample) == noErr, let sample else {
            throw FixtureError.buffer
        }
        return sample
    }

    enum FixtureError: Error { case writer, buffer, audioTrack(Int) }
}

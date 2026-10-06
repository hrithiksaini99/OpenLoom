@preconcurrency import AVFoundation
import Observation
import OpenLoomCore

@MainActor @Observable
final class PlaybackController {
    let player = AVPlayer()
    private(set) var time: Double = 0
    var captionsEnabled = true
    private var observer: Any?

    func load(url: URL, root: URL) throws {
        detach()
        try LocalFilePolicy.requireContained(url, in: root)
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.time = max(0, time.seconds.isFinite ? time.seconds : 0) }
        }
    }
    func seek(to seconds: Double) {
        time = max(0, seconds)
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func detach() {
        player.pause()
        if let observer { player.removeTimeObserver(observer); self.observer = nil }
        player.replaceCurrentItem(with: nil)
        time = 0
    }
}

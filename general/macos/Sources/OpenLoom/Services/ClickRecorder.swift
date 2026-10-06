import AppKit
import OpenLoomCore
@preconcurrency import ScreenCaptureKit

/// Captures click positions only, while recording a selected display. No keys or text are observed.
@MainActor
final class ClickRecorder {
    private var monitor: Any?
    func start(filter: SCContentFilter, onClick: @escaping @MainActor (UnitPoint2D) -> Void) {
        stop()
        // Moving windows need live coordinate updates. Display recording has a stable coordinate space.
        guard #available(macOS 15.2, *), filter.style == .display,
              let display = filter.includedDisplays.first, display.frame.width > 0, display.frame.height > 0 else { return }
        let frame = display.frame
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated {
                let location = NSEvent.mouseLocation
                let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
                let p = CGPoint(x: location.x, y: desktopTop - location.y)
                guard frame.contains(p) else { return }
                onClick(UnitPoint2D(x: (p.x - frame.minX) / frame.width, y: (p.y - frame.minY) / frame.height))
            }
        }
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
}

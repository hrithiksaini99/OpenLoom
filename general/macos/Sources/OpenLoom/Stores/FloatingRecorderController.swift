import AppKit
import Observation
import SwiftUI

/// AppKit handles floating-window behavior; views read the shared AppModel.
@MainActor @Observable
final class FloatingRecorderController {
    private(set) var isVisible = false
    private(set) var isCameraVisible = false
    var cameraSize: Double = {
        let stored = UserDefaults.standard.double(forKey: "floatingCameraSize")
        return [180.0, 240.0, 300.0].contains(stored) ? stored : 240.0
    }() {
        didSet { UserDefaults.standard.set(cameraSize, forKey: "floatingCameraSize"); resizeCamera() }
    }
    @ObservationIgnored private var recorderPanel: NSPanel?
    @ObservationIgnored private var cameraPanel: NSPanel?

    func showRecorder(model: AppModel) {
        if recorderPanel == nil {
            let panel = makePanel(size: .init(width: 482, height: 90), title: "OpenLoom floating recorder", autosave: "OpenLoom.FloatingRecorder")
            panel.contentView = DraggableHostingView(rootView: FloatingRecorderView(model: model))
            recorderPanel = panel
        }
        isVisible = true
        recorderPanel?.orderFrontRegardless()
    }

    func hideRecorder() { isVisible = false; recorderPanel?.orderOut(nil) }

    func showCamera(model: AppModel) {
        if cameraPanel == nil {
            let panel = makePanel(size: .init(width: cameraSize, height: cameraSize), title: "OpenLoom camera preview", autosave: "OpenLoom.CameraPreview")
            panel.contentView = DraggableHostingView(rootView: FloatingCameraView(model: model))
            cameraPanel = panel
        }
        isCameraVisible = true
        resizeCamera()
        cameraPanel?.orderFrontRegardless()
    }
    func hideCamera() { isCameraVisible = false; cameraPanel?.orderOut(nil) }
    func resizeCamera() { cameraPanel?.setContentSize(.init(width: cameraSize, height: cameraSize)) }

    func sync(model: AppModel) {
        if model.recorder.phase == .choosingSource {
            recorderPanel?.orderOut(nil); cameraPanel?.orderOut(nil)
        } else {
            if isVisible { recorderPanel?.orderFrontRegardless() }
            if isCameraVisible, model.recorder.settings.mode.usesCamera { cameraPanel?.orderFrontRegardless() }
            else { cameraPanel?.orderOut(nil) }
        }
    }

    func closeAll() {
        recorderPanel?.orderOut(nil); cameraPanel?.orderOut(nil)
        recorderPanel?.contentView = nil; cameraPanel?.contentView = nil
        recorderPanel?.close(); cameraPanel?.close()
        recorderPanel = nil; cameraPanel = nil
    }

    /// Generated-content acceptance checks only our windows, without UI event injection.
    func verifyWindowBehavior(model: AppModel) throws {
        let original = isVisible
        showRecorder(model: model)
        guard let panel = recorderPanel, panel.isVisible, panel.level == .floating,
              panel.isMovable, panel.isMovableByWindowBackground, !panel.hidesOnDeactivate,
              panel.collectionBehavior.contains(.canJoinAllSpaces),
              panel.collectionBehavior.contains(.fullScreenAuxiliary) else { throw CocoaError(.validationMissingMandatoryProperty) }
        let frame = panel.frame
        panel.setFrameOrigin(.init(x: frame.minX + 20, y: frame.minY + 20))
        hideRecorder(); showRecorder(model: model)
        guard abs(panel.frame.minX - frame.minX - 20) < 1 else { throw CocoaError(.validationNumberTooSmall) }
        panel.setFrame(frame, display: true)
        if !original { hideRecorder() }
        let originalCamera = isCameraVisible, originalSize = cameraSize
        showCamera(model: model)
        defer {
            cameraSize = originalSize
            if !originalCamera { hideCamera() }
        }
        guard let camera = cameraPanel, camera.level == .floating, camera.isMovableByWindowBackground,
              camera.collectionBehavior.contains(.canJoinAllSpaces) else { throw CocoaError(.validationMissingMandatoryProperty) }
        for size in [180.0, 240.0, 300.0] {
            cameraSize = size
            guard abs(camera.frame.width - size) < 1, abs(camera.frame.height - size) < 1 else { throw CocoaError(.validationNumberTooSmall) }
        }
    }

    private func makePanel(size: CGSize, title: String, autosave: String) -> NSPanel {
        let panel = RecorderPanel(contentRect: .init(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = title; panel.isReleasedWhenClosed = false
        panel.level = .floating; panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false; panel.worksWhenModal = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isMovable = true; panel.isMovableByWindowBackground = true; panel.acceptsMouseMovedEvents = true
        panel.setFrameAutosaveName(autosave)
        if !panel.setFrameUsingName(autosave), let screen = NSScreen.main {
            panel.setFrameOrigin(.init(x: screen.visibleFrame.minX + 32, y: screen.visibleFrame.minY + (autosave == "OpenLoom.CameraPreview" ? 144 : 32)))
        }
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }), let screen = NSScreen.main {
            panel.setFrameOrigin(.init(x: screen.visibleFrame.minX + 32, y: screen.visibleFrame.minY + 32))
        }
        return panel
    }
}

private final class RecorderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

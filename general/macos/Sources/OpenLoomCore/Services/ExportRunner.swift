@preconcurrency import AVFoundation
import Foundation

public typealias MediaProgress = @Sendable (Double) async -> Void

/// AVFoundation owns the export worker. This box is shared only for its thread-safe cancellation
/// and progress sequence; the actor configures the session before starting it.
private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}

private final class ExportHeartbeat: @unchecked Sendable {
    private let lock = NSLock()
    private var lastProgress = 0.0
    private var lastChange = ProcessInfo.processInfo.systemUptime
    private(set) var timedOut = false

    func update(_ fraction: Double) {
        lock.withLock {
            if fraction > lastProgress + 0.000_001 {
                lastProgress = fraction
                lastChange = ProcessInfo.processInfo.systemUptime
            }
        }
    }
    func check() -> Bool {
        lock.withLock {
            if ProcessInfo.processInfo.systemUptime - lastChange > 60 { timedOut = true }
            return timedOut
        }
    }
    var expired: Bool { lock.withLock { timedOut } }
}

extension MediaExporter {
    func runExport(_ session: AVAssetExportSession, to destination: URL, as type: AVFileType,
                   estimatedDuration: Double, progress: MediaProgress? = nil) async throws {
        try Task.checkCancellation()
        let box = ExportSessionBox(session), heartbeat = ExportHeartbeat()
        let updates = Task {
            for await state in box.session.states(updateInterval: 0.25) {
                guard !Task.isCancelled else { return }
                if case .exporting(let value) = state {
                    let fraction = min(1, max(0, value.fractionCompleted))
                    heartbeat.update(fraction)
                    if fraction < 1 { await progress?(fraction) }
                }
            }
        }
        let export = Task {
            try await withTaskCancellationHandler {
                // Also bounds a failure of the progress sequence itself. No child task is joined on timeout.
                try await AsyncDeadline.run(timeout: .seconds(max(120, estimatedDuration * 20 + 60))) {
                    try await box.session.export(to: destination, as: type)
                }
            } onCancel: { box.session.cancelExport() }
        }
        let watchdog = Task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                if heartbeat.check() { export.cancel(); return }
            }
        }
        defer { updates.cancel(); watchdog.cancel() }
        do {
            try await withTaskCancellationHandler { try await export.value } onCancel: { export.cancel() }
            try Task.checkCancellation()
            await progress?(1)
        } catch {
            box.session.cancelExport()
            if heartbeat.expired { throw OpenLoomError.processingTimedOut }
            throw error
        }
    }
}

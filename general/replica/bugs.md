# Reproduced bugs and repair evidence

Build: OpenLoom 0.4.0 (5), macOS 27.0.1/Apple Silicon. The initial publication contains these repairs; no earlier Git commits existed. This file reports only observed failures. Open acceptance items appear separately in [test-plan.md](test-plan.md).

## BUG-001: Camera pause/stop hangs in a preview/session lock cycle

- Severity: S1, core flow blocked. Flow F02/F03; S01–03/S08.
- Steps: start camera preview/recording; pause or stop and tear down the preview.
- Expected: finalize the current take and return responsive controls.
- Actual: main thread waited during AVCaptureVideoPreviewLayer teardown; camera queue waited in AVCaptureSession.stopRunning for main-thread work.
- Evidence: local `.build/OpenLoom-hang.sample.txt`; prior captured process stacks. Private process samples are excluded from Git.
- Fix: one private camera queue, image-only preview publication, no capture session/layer in SwiftUI, bounded operations with one-shot completion.
- Status: repaired in this publication; final authorized camera lifecycle passed with pause 0.150480 s and stop/save 0.266028 s. Does not prove screen/audio/long-session acceptance.

## BUG-002: Saved camera video crashes when SwiftUI VideoPlayer mounts

- Severity: S1, core review blocked. Flow F03/F04; S05.
- Steps: finish the first real camera test; open its recording; reopen the app/recording.
- Expected: saved video opens in the player.
- Actual: process aborted in system `_AVKit_SwiftUI` generic metadata initialization; reopen reproduced it after MP4 had saved.
- Evidence: local macOS DiagnosticReports and private acceptance run; no footage distributed.
- Fix: AVPlayerView through a narrow AppKit representable; disabled sharing and paused-frame analysis.
- Status: repaired; actual mounted player advanced with generated media and the final camera video.

## BUG-003: Floating preview toggle unexpectedly ends camera recording

- Severity: S1, take interrupted. Flow F02; S03.
- Steps: start a camera take; hide/re-enable the floating preview.
- Expected: video capture continues; only displayed preview changes.
- Actual: first diagnostic take ended at 0.16668 s; test timed out. The playable short take and raw sources remained local.
- Evidence: local failed acceptance metadata and framework log stack through CameraRecorder.setPreviewEnabled/commitConfiguration.
- Cause: changing AVCaptureConnection.isEnabled rebuilt the camera graph during recording.
- Fix: keep the output connection fixed; gate only frame conversion/publication. Do not reconfigure the capture session for preview visibility.
- Status: repaired; two subsequent real tests passed. Retained CameraAcceptanceCheck verifies the actual AppModel preview action on/off/on during a take.

## BUG-004: White Record label has insufficient contrast

- Severity: S3, visible accessibility issue. S01/S02.
- Steps: run Replica contrast check on white text and `#ed5e52` action tint.
- Expected: ≥4.5:1 for normal white labels.
- Actual: 3.32:1.
- Evidence: static checker reproduced failure before repair.
- Fix: separate decorative brand coral from `recordingAction` (`#c63d32`); all Record/Stop tints use it. Add a scrim to the camera placeholder caption.
- Status: fixed; new explicit pairs pass. Native material/disabled/semantic-color accessibility remains unverified.

## To check (not reproduced bugs)

Screen/audio capture, long recordings, abrupt termination, disk pressure, permission revocation, camera/display disconnect, sleep/lock, recognition, physical dragging, multi-Space/fullscreen use, keyboard/VoiceOver and minimum-OS/Intel compatibility. No open reproduced S1/S2 is currently known after the repairs; this is not evidence that none remain. The incomplete must-have acceptance gates keep the release verdict **not shippable**.

# OpenLoom 0.4 recording repair and floating UI validation

Validated on 5–6 October 2026: macOS 27.0.1 (26A434), Apple Silicon, Apple Swift 6.4 Command Line Tools. Deployment target is macOS 15.2; Intel and an actual macOS 15.2 device have not been tested. The bundle is ad-hoc signed for local development.

## Established failures and repairs

1. A live process sample established a lock cycle between the main thread tearing down `AVCaptureVideoPreviewLayer` and the camera queue in `AVCaptureSession.stopRunning`. Preview now supplies throttled images; views never retain the capture session or a preview layer.
2. The first authorized real camera test saved its MP4, then the process aborted inside system `_AVKit_SwiftUI` generic metadata initialization while mounting `VideoPlayer`. Reopening reproduced that crash site. Playback now uses AppKit `AVPlayerView`; the final camera test verified the actual controller mounted in the main review window.
3. Pause previously composited camera video and the UI hid the main window/transport. Pause now journals a source take, compositing is deferred to stop/recovery, and controls remain visible outside scrolling content.
4. The first floating-preview test ended a take after 0.16668 seconds. Local framework logs show `setPreviewEnabled` rebuilding the capture graph when it changed `AVCaptureConnection.isEnabled`. Preview toggles now gate image generation without changing capture connections during a take. The short test video and sources were retained. Two subsequent real camera tests passed with preview on/off/on, pause/resume, save and native playback.
5. One camera authorization wait was delayed overnight. Already authorized access now bypasses another permission request, and undetermined requests have a 60-second deadline. The fresh final test's three preview cycles completed in 3.131, 0.718 and 0.764 seconds. The undetermined-permission timeout has not been exercised by resetting OS permissions.

Original diagnostic evidence remains local in `.build/OpenLoom-hang.sample.txt` and the macOS DiagnosticReports directory. The first failed test's saved media and original takes were retained. The [source-based competitor review](../research/capture-reliability-comparison.md) explains these failures and the architectural changes.

## Passed

| Check | Evidence and scope |
| --- | --- |
| Repeatable local verification | `./script/verify.sh` completed: tests, optimized staged build, strict signing check, signed privacy audit and runtime sandbox probe. It does not open devices or replace the live app. |
| Core tests | **35 tests in 6 suites passed** after the final UI contrast repair, execution 1.550 seconds excluding compilation; `.build/replica-final-verification.log`. Optimized build, strict signing, signed privacy audit and runtime sandbox probe passed in the same run. |
| Deadlines and cancellation | A missing/noncooperative callback returns on deadline or cancellation without joining its worker. Late completion does not double-resume the caller. |
| Late export completion | A generated-media export held after AVFoundation completed was cancelled; releasing that worker afterward did not promote output. Original bytes stayed unchanged and temporary export files were removed. |
| Segment assembly and trim | Generated red/blue takes assembled in order, frames checked around the join, independent audio tracks preserved. Trim duration/frames checked and original bytes preserved. Existing destinations and invalid input are rejected. |
| Recovery | Finished sources with missing metadata checkpoints are discovered. An existing finished output repairs metadata without being replaced. Missing camera sources allow explicit screen-only recovery. Cancelled recovery retains originals and does not mark output ready. |
| Camera composition | Generated camera MOV is remuxed to actual MP4, audio retained. Circular mask, positive/negative camera offsets, preserved screen audio and source bytes checked. This is not a live synchronization/drift benchmark. |
| Visual editing | Timed drawing and zoom alter frames only within their cues; editor renderer and exported frames agree; originals stay unchanged. |
| Captions and review | Timestamp validation, search, markup escaping, back-compatible manifests, SRT/VTT/Markdown exports and owner-only permissions checked. Speech audio is mixed locally; silent input is rejected. Actual recognition has not been exercised. |
| Storage and paths | Private metadata/file permissions, corrupt-session isolation, UUID paths, missing-output handling, symlink escapes, remote/nonlocal paths and invalid settings checked. |
| Signed app workflow | `--studio-check` passed inside the installed sandboxed app: generated demo, actual mounted playback advancing, note creation/removal, library search, trim, drawing/zoom export, captions and review export. Export busy state cleared on completion. |
| Generated UI layout | App-owned NSHostingView fixtures rendered at default/minimum detail sizes, in light/dark appearance, with setup, camera configuration, transcript, notes and review layouts. No desktop or camera image was read for layout inspection. |
| Floating windows | Installed-app check confirmed floating level, nonactivation, background-drag configuration, Space/fullscreen flags, retained recorder position after hide/show and camera resizing to 180/240/300 points. These are configuration/programmatic checks, not physical dragging or multi-Space acceptance. |
| Closed studio | Generated check closed/reopened the main studio while floating controls and shared state remained. Native UI inspection separately verified the visible capsule, its options menu, and reopening the same review view through **Open studio**. |
| Real camera lifecycle | Explicitly authorized camera-only test, default built-in camera, H.264/720p/30 fps, microphone/system audio/click capture off. Three preview start/stop cycles, five-second take → pause → resume → five-second take → stop all completed. |
| Recording preview | The camera button's actual AppModel action enabled, hid and re-enabled the floating preview during recording. Frames arrived after both enables; hiding cleared frames and left the engine recording. Stop cleared all preview/recording flags and released the camera without requiring restart. |
| Camera media/playback | Final ready MP4: **10.56783 seconds**, **2 source takes**, **0 audio tracks**. One frame decoded locally on each side of the join; actual mounted native playback advanced. No pixels entered reports/tool output. |
| Camera pause/stop latency | Pause **0.150480 seconds**, stop/save **0.266028 seconds** for the final short camera-only test. These are observations from one run, not long-recording or comparative performance claims. |
| Post-camera responsiveness | The final repaired-camera process was sampled for two seconds: main thread idle in its normal event loop, with no preview/session lock cycle in that sample. Local evidence: `.build/OpenLoom-0.4-camera-passed.sample.txt`. This is a point observation, not a memory/energy benchmark. |
| Privacy | Signed App Sandbox enabled; camera/audio input entitlements; no network client/server or temporary exception. Production sources contain none of the audit's listed network, webview, browser-opening, process-launch, server speech or asset-download APIs. |
| Runtime network denial | Separate diagnostic app signed with the same entitlements received a sandbox denial for a no-payload loopback connection. No external host or recording was sent. |
| Native playback analysis | `AVPlayerView.allowsVideoFrameAnalysis` and its sharing-service button are disabled. Playback does not request AVKit's paused-frame object/text analysis. |
| Explicit color pairs | Replica's contrast checker reproduced white-on-brand-coral at 3.32:1; all Record/Stop tints now use a separate darker action token at 5.10:1. Camera placeholder text has a black scrim. All four explicit static pairs pass; native glass/disabled/semantic-color accessibility is unverified. |
| Safe packaging | Ordinary packaging refuses to replace a running OpenLoom. Staging builds a separate bundle. Completed diagnostic processes were checked for media writes before installation; previous app bundles and all recording sources were retained. |

Metadata-only evidence is in [acceptance-2026-10-06.json](Validation/acceptance-2026-10-06.json). Reports contain no footage, camera frames, personal transcript or recording-library inventory. Hardware camera footage stays in the private local library; tests never read an existing personal recording.

The native automation transport initially returned `native pipe closed before response`; it later became available for the recorder menu and studio-close/reopen checks. Coordinate drag gestures against a lone `NSPanel` returned `noWindowsAvailable`, so physical dragging remains unverified. No alternative event-injection mechanism was used. AppKit video and glass surfaces are not fully drawn by the offscreen fixture renderer; native playback and the visible floating capsule were inspected separately. Camera footage was never included in UI screenshots.

## Reproduce locally

```bash
./script/verify.sh
# Quit normally before installing dist/OpenLoom-next.app as dist/OpenLoom.app.
open -n dist/OpenLoom.app --args --studio-check
```

The studio check creates a labeled generated sample and private exports. It opens no recording device. Its report is `UIDiagnostics/studio-check.json` under OpenLoom's container Application Support directory.

With explicit consent and macOS permissions, the device acceptance commands are:

```bash
open -n dist/OpenLoom.app --args --camera-lifecycle-check
open -n dist/OpenLoom.app --args --screen-lifecycle-check
```

Camera check records approximately ten seconds locally with microphone off. Screen check is restricted to a window of generated graphics owned by that app process, with camera, microphone and system audio off. It needs macOS screen-recording access. Reports are `camera-check.json` and `screen-check.json` alongside the private Recordings folder. Normal launches never start these checks. Run one check at a time in a fresh app process.

## Remaining acceptance

- Screen lifecycle test is compiled but has not yet run; approval was requested separately because the earlier authorization covered camera only. Real display/window capture and permission-denial behavior still need verification.
- Microphone/system audio and combined audio, camera overlays with real screen sources, attached camera changes, A/V drift and heard playback.
- Sleep/lock, external display removal, source window closure, camera disconnect, permission revocation, very short takes, low disk and interrupted writes. Fragmented MOV improves source metadata availability; arbitrary abrupt termination is not guaranteed recoverable.
- Long recordings: dropped frames, frame pacing, synchronization, CPU/GPU, energy, thermals and peak memory. No efficiency comparison to Loom or another recorder was measured.
- Actual on-device speech recognition with an installed language, accuracy/cancellation, unavailable assets; display-click coordinate mapping on multiple displays.
- Physical panel dragging, interaction with other apps and multiple Spaces/fullscreen, full mouse/keyboard/accessibility flows, minimum-OS and Intel compatibility, and distribution signing/notarization.

Do not label this development build production-ready, feature-equivalent to Loom, or faster than another recorder from these results.

## Deliberate product boundaries

Local-only storage/processing; no remote sharing, analytics, comments, cloud integration, localhost server, remote AI or automatic updates. Floating controls/preview, app-scoped shortcuts, preset encoded camera position/size, timed post-recording visual edits and installed Apple speech assets are implemented. Dragging/hiding preview changes only its window; recorded camera composition remains enabled with its preset position. Live encoded overlay changes, global hotkeys, region capture, mic chooser/meters, continuous cursor tracks, live drawing, timeline cuts, subtitle burn-in, redaction and local summaries remain future work.

Pause starts a new take on resume; it is not frame-perfect seamless pause. Source takes and exports increase disk usage and are deliberately retained. Camera overlays re-encode at stop, with progress/deadlines/cancellation; long-export cost remains unmeasured. Continuity Camera sources are excluded; virtual camera providers and OS backups remain outside the application's network boundary.

SwiftPM's build-manifest sandbox is disabled for this managed build environment; the signed application sandbox remains enabled. The `ViewState` alias avoids the CLT/macOS 27 `State` macro collision. The test script supplies the installed Testing macro plugin search path. Two missing developer search-directory linker warnings did not prevent builds/tests. No global toolchain selection, OS permission setting or security protection was altered by the agent.

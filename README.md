# OpenLoom

A native, local-only macOS walkthrough app: capture, captions, review, and visual editing. MIT licensed. SwiftUI, ScreenCaptureKit, AVFoundation, Core Image, and on-device Speech. No third-party runtime packages, account, backend, telemetry, or network permissions.

This is a **0.4 development build**. OpenLoom is a working name; another public project uses a similar name. The repaired camera preview → pause/resume → save → native playback flow has passed on this Mac. Long-recording and broader device/audio acceptance remain before a public release.

## Research

Read [the Loom and alternatives research](general/research/loom-and-local-alternatives.md) for the 18-project comparison, documented Loom architecture, license checks, local-only feasibility, build-versus-fork decision, and implementation roadmap. [The evidence ledger](general/research/source-ledger.json) records checked repository identities and file hashes.

The [recording reliability review](general/research/capture-reliability-comparison.md) compares actual capture/recovery code in Cap, QuickRecorder, and OpenCapture, explains both observed failures, and documents the repair. No competitor code was copied.

The [Replica comparison and build plan](general/replica/plan.md) maps Loom's documented workflows to our native UI, with a feature matrix, design tokens, reproduced bugs and acceptance gates. Current scoped coverage is 51.9%; screen/audio/long-recording validation and live encoded-camera controls remain significant gaps. No matched Loom screenshot pair was available, so there is no numeric visual similarity claim.

## Implemented

- Native macOS source picker for one display or window.
- **Screen, screen + camera, and camera-only modes**. Camera chooser, opt-in live preview, mirroring, and circular bubble position/size controls.
- H.264 or HEVC MP4 capture at 720p, 1080p, or 4K, capped to the source size; 15/30/60 fps.
- Optional system audio and default-device microphone; cursor toggle and countdown.
- Menu-bar start/pause/resume/stop controls; app-scoped keyboard commands.
- A draggable floating recorder with source selection, microphone setup, camera preview, elapsed time, pause/resume, chapter marking, stop/save, and processing cancellation. Native nonactivating panels keep it available above normal windows and across Spaces. **⌥⌘R** shows/hides it while OpenLoom is active.
- A separate draggable circular camera preview with three sizes. Preview can be hidden during camera recording without stopping the take. Its screen position is independent of the camera position encoded in the recording.
- Original ribbon icon, coral/violet palette, rounded source cards, and system glass on the floating controls on macOS 26+ (material fallback on older supported versions).
- Persistent recording controls stay visible outside scrolling content, including while browsing another recording. The main window stays open during capture.
- Pause finalizes and journals a source take. Resume starts another. Stop renders camera overlays when needed and assembles the completed takes locally.
- Bounded capture/finalization operations, export progress, cancellation, and recovery that retain source files.
- On-device captions on macOS 26+ using **already installed** SpeechTranscriber assets. No asset downloader or server fallback. Caption correction, timestamp search/seek, playback captions, SRT and WebVTT exports.
- Timestamped chapters and review notes; mark chapters while recording, edit them afterward, jump to moments, and export a Markdown review with the transcript.
- Timed pen strokes, arrows, rectangles, cursor highlights, and smooth zoom. Still-frame preview uses the same renderer as MP4 export. Edits are stored separately; a polished export preserves the original.
- Opt-in display-click positions on macOS 15.2+, automatic click highlights/zoom cues in the editor, and manual effects for window recordings. No keyboard/text monitoring.
- Persistent local library, search across titles/captions/notes, rename, native AppKit AVPlayerView playback, and Finder reveal.
- Trim start/end into a separate local MP4 while preserving originals.
- Recovery validates source takes and can discover files completed before their metadata checkpoint. Screen-only fallback is explicit if a camera take is unavailable. An unfinalized file is not guaranteed recoverable.
- Signed App Sandbox configuration with no network client/server entitlement.
- A clearly labeled generated demo with sample captions/chapters/clicks for trying review tools without capture permissions.

Camera capture uses a private AVCaptureSession on its own queue. Preview delivers images at up to 10 fps and 720×450 pixels to SwiftUI; views never hold a capture session or preview layer. Screen + camera saves separate local takes, then composites the camera at stop/recovery with a native Core Image compositor. Camera-only video uses the optional microphone; system audio is available in screen modes. Camera synchronization uses capture delegate host-clock observations and needs real-device drift validation. The encoded camera position uses presets; dragging the preview moves only its window. Display capture filters explicitly exclude OpenLoom's own windows, including its floating panels; selected-window capture includes only that window. The display exclusion path still needs real capture acceptance.

The camera chooser includes built-in and attached cameras and excludes iPhone Continuity Camera sources. OpenLoom does not initiate phone-camera connections. Third-party virtual camera providers remain services outside the app's control.

## Build and run

The app requires macOS **15.2+**. On-device captions require macOS 26+, supported hardware, and an installed speech language. The current build is verified with Swift 6.4 and the macOS 27 SDK; this SDK includes the Speech APIs used here. No dependency download is needed after the toolchain is installed. Packaging draws the app icon locally from Swift vector paths.

```bash
cd /Users/hrithik/projects/OpenLoom
./script/build_and_run.sh
```

The script builds, ad-hoc signs, audits, and opens `dist/OpenLoom.app`. It refuses to replace a running recorder. Use `--release-stage-only` to build a separate `dist/OpenLoom-next.app` while OpenLoom is open, then quit normally before installing that bundle. The Codex Run button calls this same script.

```bash
./script/build_and_run.sh --build-only
./script/build_and_run.sh --release-build-only
./script/build_and_run.sh --release-stage-only
./script/build_and_run.sh --verify
./script/test.sh
./script/verify.sh
python3 script/privacy_audit.py dist/OpenLoom.app
./dist/OpenLoomPrivacyProbe.app/Contents/MacOS/OpenLoomPrivacyProbe
```

`verify.sh` runs generated-media tests, builds an optimized separate bundle, audits signing/privacy, and runs the no-payload loopback-denial probe. It never opens recording devices. `--release-build-only` produces an optimized local bundle. `--debug`, `--logs`, and `--telemetry` are developer modes; telemetry means local OSLog events, with no upload. SwiftPM's `--disable-sandbox` flag disables its **build-manifest subprocess sandbox** to allow builds inside Codex's managed environment. It does not disable the separately signed application's App Sandbox.

Launch the `.app` bundle, not a raw `swift run` GUI executable. Bundle identity and usage descriptions matter for macOS permissions. This development signature is not an Apple distribution signature or notarization; stable release signing is a later step. Ad-hoc rebuilds may require macOS permission re-approval.

## Use

1. Choose **Screen**, **Screen + camera**, or **Camera only**. In screen modes, use **Choose source** to pick a display/window.
2. In camera modes, choose a device and optionally **Preview camera**. Set bubble position/size and mirroring. Camera access is requested only for preview/start; microphone access only for starting with the microphone enabled.
3. Press **Record**. Its persistent bottom bar shows elapsed time and recording state.
4. Use the floating recorder, bottom bar, or menu-bar icon to pause, resume, mark a chapter, or **Stop & save**. Drag the floating background to move it. Its camera button opens a circular preview; its options menu changes preview size or returns to the studio. The app-scoped chapter shortcut is **⇧⌘M**. Saving shows its stage/progress; **Cancel processing** retains source takes for recovery.
5. Select a recording. Use **Transcript** for local captions and search, or **Chapters & notes** to organize and review moments.
6. Open **Edit video**, choose a time/tool/duration, and draw on the frame. Turn **Preview edits** on to see the rendered result at that time. **Save edits** stores a recipe; **Export polished MP4** renders a new local file, with progress and cancellation.
7. Use **Export SRT / VTT**, **Export review document**, or **Trim** as needed. Exported files stay in the recording’s private exports folder.

**Open demo** generates an entirely local sample. Its captions and click positions are supplied examples, not recognition output or captured input. No devices are opened for the demo.

Explicit developer acceptance modes are documented in [VALIDATION.md](general/macos/VALIDATION.md). A normal launch never invokes them. `--studio-check` uses generated content only; camera and generated-window capture checks must be deliberately invoked with the user's consent.

The keyboard commands operate while OpenLoom is the active app. Floating controls remain available when another application is active; system-wide hotkeys remain future work. A window closing, protected media, revoked permissions, sleep, or a removed display can interrupt capture. Audio echo is possible when a microphone also hears speaker output; headphones help.

## Privacy boundary

All runtime files are stored under the sandbox container's Application Support directory:

```text
~/Library/Containers/org.openloom.local/Data/Library/Application Support/OpenLoom/Recordings/
  <UUID>/
    manifest.json
    recording.mp4
    segments/segment-0000.mp4       # finalized playable segment
    segments/screen-0000.mp4        # retained screen source in camera mode
    segments/camera-0000.mov        # retained camera source
    exports/trim-<UUID>.mp4
    exports/polished-<UUID>.mp4
    exports/captions-<UUID>.srt
    exports/captions-<UUID>.vtt
    exports/review-<UUID>.md
```

The **Show library in Finder** action resolves the actual location on your Mac. Folders use private permissions and metadata/finished media are owner-readable/writable. Titles never become file paths. Library paths reject traversal, linked folders that escape the library, iCloud items, and nonlocal volumes.

OpenLoom has no uploader, browser-opening links, local HTTP server, model downloader, or external process runner. It does not capture anything on launch. SpeechTranscriber processes recordings on-device; installed-language and asset checks fail closed when unavailable. Only its on-device analyzer is used. Temporary audio prepared for captions is removed when the operation finishes/cancels.

Export destinations stay inside the private library. OS backups, system-managed speech-asset updates, and files you copy elsewhere are controlled outside the app. Application network isolation cannot make a whole-machine guarantee about those services.

`privacy_audit.py` checks the **signed artifact**, not just the source plist. `OpenLoomPrivacyProbe` is a separate diagnostic executable signed with identical entitlements; it attempts a no-payload loopback connection and must receive a sandbox denial. It does not send recordings or connect to an external host. These checks are targeted regression evidence, not a complete network/security audit.

## Project structure

```text
Package.swift
general/research/             # product research and evidence
general/replica/              # Loom comparison, design system and next build plan
general/macos/Sources/
  OpenLoom/App/               # scenes and lifecycle
  OpenLoom/Views/             # capture, camera preview, playback, review, visual editor
  OpenLoom/Services/          # screen/camera capture and click callbacks
  OpenLoom/Stores/            # app, camera and playback state
  OpenLoomCore/               # metadata, local paths, captions, GPU composition, demo
general/macos/Tests/          # synthetic-media and storage tests
general/macos/Config/         # bundle metadata and sandbox entitlements
general/macos/Diagnostics/    # separate privacy probe
script/                      # reproducible build, test and audit entry points
```

## Next milestones

1. Interactive capture/audio permission and long-recording validation.
2. Region capture, microphone device chooser/meters, free encoded camera positioning, and global hotkeys.
3. Timeline cuts, continuous cursor tracks, live drawing, subtitle burn-in, and verified redaction.
4. User-supplied Whisper models for broader hardware/language coverage and optional local summaries.
5. Performance/accessibility testing and signed release packaging.

No third-party model is included or downloaded. The caption implementation uses installed Apple speech assets. Public sharing, remote comments/analytics, and cloud integrations are outside the strict local-only product.

See [validation and remaining checks](general/macos/VALIDATION.md). The test suite generates solid-color clips and sine-wave audio; it never records the screen, camera, microphone, or other people's data.

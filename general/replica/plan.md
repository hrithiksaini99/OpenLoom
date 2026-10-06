# Loom differences and the next build order

The biggest difference is trust in the recording flow. A nicer floating UI helps, but the release gate is a usable video after pause/stop, with recoverable finalized takes if processing fails. The known camera deadlock, playback crash and preview-toggle interruption were repaired and checked on this Mac. We still need real screen/audio, long-session and interruption acceptance before calling this dependable.

Applied [Replica](https://github.com/Jakeschincariol/replica-skill): nine screen roles, six flows, a weighted feature matrix, native architecture/design mapping, reproduced bugs and flow tests. Current local feature coverage is **51.9/100**, with **5 of 12 must-haves complete** and seven partial. Eight cloud rows and three OpenLoom additions do not affect the score. This deliberately conservative score includes essential unverified capture behavior as partial. It is not a percentage estimate of engineering effort or a performance benchmark. Full computed detail: [parity.md](parity.md).

## What differs in daily use

| Task | Loom, from public documentation | OpenLoom now | Decision |
| --- | --- | --- | --- |
| Start a walkthrough | Screen/window/custom size, camera choice and microphone source/audio indicator | Native display/window picker; three modes; default microphone only; no meter | Keep native OS picker; add region capture and explicit audio preflight. [Loom desktop guide](https://support.atlassian.com/loom/docs/get-started-with-the-loom-desktop-app/) |
| Keep controls near the work | Movable recorder and camera presentation | Original ribbon/glass capsule and separate circular preview; shared state, timer, pause/stop/menu | Implemented; physical drag, fullscreen/Spaces and capture exclusion need acceptance. [Historical desktop redesign](https://www.atlassian.com/blog/loom/redesigned-desktop-app-record-loom), not a measurement of current appearance. |
| Move/hide a presenter during a take | Camera can be added/removed while recording | Preview can be hidden safely; encoded camera remains on and uses corner/size presets | Add explicit timestamped recorded-camera placement/visibility controls. Preview movement must not pretend to change the exported composition. [Capture modes](https://support.atlassian.com/loom/docs/use-looms-different-capture-modes/) |
| Pause and finish | Pause/resume, then review/distribute video | Pause checkpoints a take; resume creates another; stop composes locally with visible progress/cancel | Keep source preservation; finish screen/audio/long-session acceptance. [Pause/resume](https://support.atlassian.com/loom/docs/pause-and-resume-while-recording/) |
| Correct a walkthrough | Waveform cuts/stitch and transcript-driven removal | Begin/end trim plus timed drawing/zoom into separate exports | Add nondestructive multi-cut timeline before text-driven editing. [Loom editor](https://support.atlassian.com/loom/docs/edit-your-loom-video/) |
| Find a spoken moment | Timed transcript, search/correction and captions | Same local review roles; recognition uses installed Apple assets; sample pipeline tested | Verify real recognition; add availability UI and later user-supplied local models. [Loom captions](https://support.atlassian.com/loom/docs/loom-video-transcription-and-closed-captions/) |
| Share and collaborate | Hosted links, remote access and engagement | Local MP4/SRT/VTT/Markdown files, private library | Keep cloud features excluded. Export cannot become an implicit upload. [Loom sharing](https://support.atlassian.com/loom/docs/share-your-recording/) |

Visual comparison is qualitative, based on documented roles and our inspected/generated UI. The browser connector denied the original public page; no matched viewport/state pair was captured. Replica's layout score is therefore **unavailable**, not zero or a fabricated match. Our component sizes are measured in our code; no Loom pixels, logos or copy are used.

## Five priorities, in order

### M1 — Recording reliability and acceptance

Screens S01–05/S08–09; flows F01–03/F06. Use the retained diagnostics to check one generated window first, then explicit screen/audio/camera combinations. Exercise repeated pause/resume, short takes, 30–60 minute captures, permission loss, sleep/lock, window/display/device removal and disk pressure. Record metadata-only timing/frame/sync/CPU/memory/energy evidence. Never benchmark Loom without running the same input on both products.

Done when every applicable must-have acceptance case in [test-plan.md](test-plan.md) passes, the exported video is playable/audible and sources survive failures. Any reproduced S1/S2 gets a retained regression before more feature work. Preserve existing ready MP4s; no promise that arbitrary unfinalized/corrupt media can be recovered. Verify our windows are excluded from display capture.

### M2 — Recorded camera behavior that matches the preview

Screens S01–03; F02/F05. Add normalized placement/size/visibility events to the saved edit recipe. Distinguish **preview only** from **recorded bubble** visibly. Dragging a recorded bubble must map to source coordinates, including Retina and multiple displays; clamp geometry and retain preset reset. Support recorded-camera on/off while a screen take continues, without touching AVCaptureConnection.isEnabled or rebuilding a running graph. Preserve raw screen and camera takes and apply events during composition.

Done when generated cue-frame checks and authorized combined capture verify event boundaries/geometry, export matches the selected behavior and hiding only a preview never ends a take. If a camera becomes unavailable, preserve the screen take and offer an explicit fallback. Account for source dimensions changing; do not couple desktop window coordinates directly to video pixels.

### M3 — Confident setup and fast floating control

Screens S01–03/S09; F01/F02/F06. Add microphone device selection, live levels before start, clear mic/system source labels, an explicit test-audio action, region capture, configurable global recording hotkeys, and speaker notes/live annotation controls. Add a safe restart command that retains the abandoned take unless the user explicitly deletes it. Keep the compact capsule legible; advanced options live in a native popover/menu.

Done when no-input/device-change cases are visible, meters reflect the selected input, preflight never records implicitly, conflicting hotkeys are explained, region/cursor coordinates map correctly and cross-app commands work. Verify keyboard and VoiceOver access, small displays, multiple Spaces/fullscreen and Reduced Transparency/Increased Contrast. Physical panel dragging remains an acceptance case, not a config-flag assertion.

### M4 — A useful nondestructive editor

Screens S05/S07/S08; F05. Add ordered cut ranges, waveform/undo, stitch local clips, precise playhead editing and saved recipes. Extend timed annotation controls, optional subtitle burn-in and verified blur/redaction. Drawing opaque boxes is not a redaction guarantee. Later add local silence/filler suggestions that the user reviews before applying.

Done when generated tests verify timeline joins, audio continuity, undo, edit boundaries and source preservation, and every export/cancel path releases its busy state. For redaction, test all exported frames throughout the affected interval. Long media must not load an entire frame sequence into memory.

### M5 — Verified local speech and library organization

Screens S04–06/S09; F04. First validate installed-language recognition, cancellation, timestamp accuracy and offline failure states on this Mac. Then add folders/tags and saved local transcript search. Optional Whisper/local summaries require a user-supplied model and an explicit feature switch; no downloader or hosted fallback. Keep manual chapters/notes useful without AI. Speech synthesis and camera backgrounds are later optional features, not prerequisites for a trusted recorder.

Done when a real authorized local speech sample passes, uninstalled language cases give clear local guidance, captions/exports remain in the private library and no runtime networking appears. Profile indexing/recognition on supported hardware. Keep errors from blocking playback of the original.

## Release boundary

Before a distributable release: complete M1, test minimum macOS/Intel as applicable, perform full accessibility/performance review, choose a distinct permanent product name and add distribution signing/notarization. Publication of this MIT source checkpoint is not a production release. Recordings, private diagnostic samples, model weights, app binaries and Loom reference assets stay out of the public repository.

For a visual architecture walkthrough, search YouTube for **“Apple WWDC ScreenCaptureKit capturing screen content macOS”** and **“WWDC AVFoundation capture session concurrency”** on Apple's developer channel. The pipeline diagram in [architecture.md](architecture.md) maps those concepts to this implementation; demonstrations are not acceptance evidence for our build.

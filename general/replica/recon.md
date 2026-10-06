# Recon: Loom desktop → OpenLoom native macOS

Scope: choose a source → record a walkthrough → pause/resume → safely save → review, annotate and export locally. Audience: people explaining software who want their recording and processing to stay on their Mac. Public documentation establishes Loom behavior; OpenLoom code and the tests establish our behavior. Loom's internal capture pipeline is not public and was not reverse-engineered.

## Sources

Public help pages were checked on 5–6 October 2026. Documentation can describe a feature without proving its availability on every OS/plan. The historical redesign article is dated 29 August 2023 and is not evidence of the exact current layout. No account or paywall was accessed.

| ID | Primary source | What it establishes |
| --- | --- | --- |
| L01 | [Desktop guide](https://support.atlassian.com/loom/docs/get-started-with-the-loom-desktop-app/) | Recorder entry point, configuration, recording and post-recording destination |
| L02 | [Capture modes](https://support.atlassian.com/loom/docs/use-looms-different-capture-modes/) | Screen, screen + camera, camera; mode and bubble behavior |
| L03 | [Recording mode options](https://support.atlassian.com/loom/docs/choose-your-recording-mode/) | Capture scope, audio, drawing, notes and related options |
| L04 | [Camera visibility](https://support.atlassian.com/loom/docs/make-your-camera-bubble-visible-in-loom-recordings/) | Desktop camera visibility across applications |
| L05 | [Camera frame/size](https://support.atlassian.com/loom/docs/add-a-frame-to-your-camera-bubble/) | Camera presentation and resize controls |
| L06 | [Recording controls](https://support.atlassian.com/loom/docs/hide-the-recording-controls/) | Platform-specific control visibility; do not assume Mac controls are excluded from the recorded image |
| L07 | [Keyboard shortcuts](https://support.atlassian.com/loom/docs/use-looms-keyboard-shortcuts/) | Recording commands and shortcut configuration |
| L08 | [Pause/resume](https://support.atlassian.com/loom/docs/pause-and-resume-while-recording/) | Interrupt and continue a recording |
| L09 | [Editing](https://support.atlassian.com/loom/docs/edit-your-loom-video/) | Post-recording trimming/editing workflow |
| L10 | [Transcription/captions](https://support.atlassian.com/loom/docs/loom-video-transcription-and-closed-captions/) | Transcript and caption review |
| L11 | [AI features](https://support.atlassian.com/loom/docs/loom-ai-features/) | Summaries, chapters and other AI enhancements; feature/plan distinctions apply |
| L12 | [Desktop redesign, 2023](https://www.atlassian.com/blog/loom/redesigned-desktop-app-record-loom) | Historical emphasis on a movable recorder, prominent source choices and camera configuration |
| L13 | [Sharing](https://support.atlassian.com/loom/docs/share-your-recording/) | Hosted distribution after recording; excluded from our runtime scope |
| R01 | [Replica skill](https://github.com/Jakeschincariol/replica-skill) | Recon, design, test and weighted feature comparison method |
| O01 | [Open-source survey](../research/loom-and-local-alternatives.md) | 18 alternatives, licenses and local implementation feasibility |
| O02 | [Capture implementation review](../research/capture-reliability-comparison.md) | Cap, QuickRecorder and OpenCapture source findings; no competitor runtime benchmark |
| O03 | [OpenLoom validation](../macos/VALIDATION.md) | Generated tests, installed-app acceptance and authorized camera evidence |

Observation limit: the browser connector denied the Atlassian page. Original screen roles below come from the official documentation already retrieved, not a live Loom session or matched screenshot measurements. Our native empty setup, capsule/options and generated review were inspected; the 14 generated layout states were rendered locally. Click counts for Loom are unknown.

## Screen inventory

| ID | Screen / entry | Job | Shared components | Evidence / states |
| --- | --- | --- | --- | --- |
| S01 | Recorder setup / New recording | Source, audio and camera configuration before capture | Mode cards, source preview, toggles, device selector, Record | L01–03; ours: empty, camera absent, source absent, light/dark, compact generated fixtures |
| S02 | Floating recorder | Control capture while using another app | Timer, pause/resume, stop, chapter, camera, options | L01/L06/L12; ours: visible capsule/menu inspected, idle/recording/paused/saving fixtures; physical drag pending |
| S03 | Floating camera | Keep presenter visible, move/resize preview | Circular image, size menu, hide | L02/L04/L05; ours: placeholder fixture, three programmatic sizes, live frame delivery checked privately |
| S04 | Library | Find and revisit recordings | Search, list, title/status, recovery | L01; ours: generated metadata search, ready/interrupted states in source/tests |
| S05 | Player + transcript | Review a moment and locate speech | Native player, transcript search, captions, export | L09/L10; ours: actual generated and camera playback advances; sample transcript fixtures; recognition pending |
| S06 | Chapters + notes | Mark and revisit useful moments | Timestamped list, note editor, seek | L11 for chapters; ours: generated note creation/removal/export tested |
| S07 | Trim + visual editor | Produce an edited copy | Trim range, drawing tools, zoom cues, preview/export | L03/L09; ours: trim/drawing/zoom generated frame checks; full timeline cuts absent |
| S08 | Saving / interrupted recovery | Bound processing and retain usable sources | Stage/progress, Cancel, source reveal, recovery choices | Loom's detailed recovery internals unknown; ours: generated cancellation/recovery checks; arbitrary crash recovery pending |
| S09 | Settings / permissions | Control quality/privacy and resolve missing access | Quality/FPS, permissions, language availability | L01/L03/L07; ours: source configuration inspected; reset/denial hardware acceptance pending |

## Flows

| ID | Goal / screens | OpenLoom happy path | Loom difference / edge |
| --- | --- | --- | --- |
| F01 | Configure → record, S01/S09 → S02/S03 | Screen: mode → Choose source → select in OS picker → Record. Camera: mode → Record, once authorized; camera selection optional. OS picker/permission clicks vary. | L01–03 document equivalent source selection. Our device mic is default-only. Empty source blocks Record; permission/device failure must remain actionable. No measured click advantage. |
| F02 | Control a take, S02/S03 | Pause → Resume → Stop: three actions after start. Floating camera action toggles preview; options menu changes preview size. | Loom offers bubble adjustments/live recording controls. Ours saves a take at pause, composes at stop; drag/hide is preview-only and does not alter encoded camera placement. |
| F03 | Save/recover, S02 → S08 → S04/S05 | Stop → stage/progress → saved local player. If interrupted, select session → choose recovery; explicit screen-only fallback when applicable. | Loom's result leads to hosted distribution. Ours retains raw sources; bounded workers and atomic promotion protect finished files. Short real camera verified; screen, long takes and abrupt termination still pending. |
| F04 | Review/locate speech, S04 → S05/S06 | Select → generate captions or open supplied demo → search/seek; add notes/chapters. | Local installed Apple speech assets only; no remote inference. Sample caption/export pipeline verified; actual recognition pending. |
| F05 | Edit/export, S05 → S07 → S05 | Trim range → export; or Edit video → time/tool → Save edits → polished export. | Ours provides timed overlays/zoom and separate files. Missing multi-cut/stitch timeline, text-driven removal, redaction and burned-in subtitles. |
| F06 | Resume workspace, S02 ↔ S04/S01 | Close studio → use floating options → Open studio; reopen the same shared state. | Native nonactivating panel is configured for Spaces/fullscreen. Main close/reopen verified; dragging across displays/fullscreen interactions unverified. |

## Components

| Component | Variants / states | Screens |
| --- | --- | --- |
| Source card | Screen, mixed, camera; idle, selected, unavailable | S01 |
| Source preview | Empty guidance, chosen source, camera unavailable, preparing | S01/S03 |
| Transport | Ready, countdown, starting, recording, paused, saving, failed; busy actions disabled | S01/S02/S08 |
| Camera bubble | Preview, placeholder, preparing, hover hide; 180/240/300 pt | S03 |
| Library item | Ready/interrupted; selected, search match, empty library | S04 |
| Review inspector | Transcript vs notes; empty/generating/filled/error; timestamp seek | S05/S06 |
| Editor/export | Tool selection, cue range, preview, progress, cancel, failure | S07/S08 |
| Feedback | Persistent saved-source guidance, unavailable access, cancellation | All |

## Inferred product model

These are public user-facing concepts, not claims about Loom's database:

- Recording: title, creation time, duration, source and playback result. Evidence L01/L09/S04–05; confidence high.
- Recorder configuration: screen/camera mode, microphone, quality and camera presentation. Evidence L01–05/S01–03; high.
- Transcript segment: text + time interval, associated with recording. Evidence L10/S05; high.
- Chapter: recording + timestamp + label. Evidence L11/S06; high.
- Edit recipe: ranges and visual changes associated with original recording. Evidence L09/S07; medium; exact representation unknown.
- Sharing/workspace: recording access and hosted destinations. Evidence L13; high; deliberately omitted locally.
- Raw take/checkpoint: OpenLoom-specific implementation choice established by O02/O03, not inferred Loom architecture.

Relationships for our app: recording has many source takes, transcript segments, notes and visual cues; settings are snapshotted at recording creation. No user/account or remote ownership model exists; the OS user and private sandbox library provide the local access boundary.

## Scope and size

Nine screen roles, six flows, five public local data concepts plus OpenLoom's source checkpoints. This is a large native product, with reliability/energy/device validation as the hardest part; source clock alignment and cancellable rendering are next. Adding every Loom capability would be an ongoing product program, not a quick UI clone.

Cloud links, uploads, remote comments/analytics, accounts, meeting bots, hosted AI, integrations and partner content are out of scope. System-managed speech assets must already exist; no model downloads. The current [feature matrix](features.csv) is the tracked difference list and [plan](plan.md) sequences the work.

# Native design system and comparison

The Loom reference establishes component **roles and interactions**. No matched source screenshot was available to measure Loom's spacing, color, font or layout. Dimensions below are measured from our SwiftUI code/fixtures. Replica's CSS/Tailwind output is replaced by [StudioStyle.swift](../../macos/Sources/OpenLoom/Views/StudioStyle.swift), semantic AppKit/SwiftUI styles and [tokens.json](tokens.json).

## Character and hierarchy

An original looping ribbon appears in the icon/sidebar/capsule. Coral/violet are decorative brand colors; a darker coral defines recording actions. Native rounded headings and restrained source cards make source selection the first task. A persistent bottom transport owns the main action; the floating capsule owns compact control while another app is active. Secondary configuration belongs in the source setup or options menu, not an expanding row of unlabeled buttons.

The camera preview is a separate circular window. Its label has a black scrim; its image is masked and ringed. Preview and encoding currently differ: preview drag/resize/hide does not edit encoded camera position/size/visibility. The UI help explains that limit. Milestone M2 connects explicit recorded-overlay controls to timestamped composition events; it must not silently change a saved recording merely because a preview moved.

## Component specification

| Component | Native implementation / tokens | States and accessibility |
| --- | --- | --- |
| Record / Stop & save | Native bordered prominent capsule; `recordingAction`; native large control in studio; compact capsule in HUD | Ready/disabled/busy; keyboard command; visible label; no action during incompatible transitions. White/action pair 5.10:1. |
| Secondary / icon action | Native bordered or borderless Button; system icon; help string | Hover, native focus, disabled; icon-only controls have help. Explicit VoiceOver traversal still pending. |
| Mode card | Rounded 20 pt card; icon/title/detail; selected accent tint/border | Screen/mixed/camera; selected, unavailable, busy. Selection indicator uses more than color. |
| Source preview | Rounded 24 pt surface, source label and camera setup | Empty and unavailable states show a next action; no silent black preview treated as ready. |
| Floating recorder | 470×78 pt inner capsule + 6 pt outer padding; 18/14 pt inner padding; 12 pt gaps; 40 pt ribbon; 105 pt status column | Timer/state, recording/paused/saving/error. Nonactivating panel; background drag enabled. Menus remain native; full keyboard-only panel access needs acceptance. |
| Floating camera | 180/240/300 pt circular panel; white 3 pt ring; 28 pt hover hide control | Preparing/available/error/hidden; image generation gated. White caption over ≥65% black scrim; hide label says recording continues. The invisible hover close button needs a complete keyboard/VoiceOver pass. |
| Library / search | Native NavigationSplitView/List/SearchField; date/duration/status text | Empty, populated, selected, interrupted and search no-result. Search on titles/transcript/notes; destructive library UI is absent. |
| Native player | Narrow NSViewRepresentable around AVPlayerView; aspect fit | Mounted ready/play/pause/seek; no sharing control or paused-frame analysis. Offscreen PNG omits its rendering; actual playback was checked separately. |
| Review inspector | Native segmented selection, scrollable transcript/notes and timestamp controls | Empty/sample/generated/processing/error. Transcript search and correction; accessible reading order/full keyboard pass pending. |
| Export progress / recovery | Stage label, progress (indeterminate or numeric), Cancel, source reveal | Busy/cancelling/completed/failed; cancellation retains source takes. Long-session timing and recovery presentation need hardware acceptance. |

## Static contrast check and limits

Replica's checker reproduced a **3.32:1** failure for white text on the previous light coral. All Record/Stop action uses now resolve to `#c63d32`, **5.10:1** with white. White captions no longer sit directly on a gradient; a 65% black scrim keeps the lightest possible composite at `#595959`. The original ribbon stroke is a graphical mark, measured against brand coral under the 3:1 UI threshold.

[contrast.json](contrast.json) is the exact static checker output. Zero failing explicit pairs does **not** certify the whole native UI: native tint rendering, disabled states, `.secondary` text, glass over arbitrary desktop content, Increased Contrast, Reduce Transparency and VoiceOver need interactive testing. We preserve system semantic colors instead of freezing sampled light-mode grays in production.

## Layout findings and next polish

- Setup now has a clear source selection, configuration and persistent Record action instead of hidden transport inside scrolling content.
- Floating controls/preview are independent windows with shared state, rather than another capture session created by UI views. Close/reopen retained the workflow.
- Compact generated fixtures are legible; labels wrap and controls remain within the setup content. Full combined main-window resizing and sidebar compression still need acceptance.
- Do not claim a numerical visual match: original and clone were not captured at the same viewport/state. The original's visual measurement and actual physical drag/multi-Space checks remain in [test-plan.md](../test-plan.md).

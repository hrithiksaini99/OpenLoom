# Flow-based acceptance plan

Build: OpenLoom 0.4.0 (5); 5–6 October 2026; macOS 27.0.1, Apple Silicon, Swift 6.4. Local generated data unless the case explicitly says authorized hardware. Swift Testing and in-app acceptance controllers replace Replica's web-specific Playwright/server/axe tooling. No test targets Loom's servers.

`PASS` describes the stated narrow case. `PENDING` means unrun, not a failing test. Source inspection is not device acceptance. Full local verification is `./script/verify.sh`; diagnostics are documented in [VALIDATION.md](../macos/VALIDATION.md).

| Case | Flow / type | Steps / expected result | Method | Result |
| --- | --- | --- | --- | --- |
| F01-H1 | Configure generated setup | Render Screen/mixed/camera, light/dark and compact layouts; usable source hierarchy/transport | `--studio-check`, fixture inspection | PASS; no device opened |
| F01-H2 | Camera happy path | Authorized built-in camera, 720p/30fps, mic off; take captured locally | `--camera-lifecycle-check` | PASS, final 10.56783 s MP4 across two takes |
| F01-H3 | Screen happy path | Only generated app-owned window, camera/mic/system audio off; start/pause/resume/stop | `--screen-lifecycle-check` | PENDING, consent/access not yet exercised |
| F01-H4 | Audio happy path | Choose known audio source, mic/system/both; hear output, inspect levels and sync | Explicit hardware session | PENDING |
| F01-E1 | Invalid source/settings | Empty source, unsupported FPS/range, non-finite dimensions; block invalid work | Core validation tests + inspected start guards | PASS at data layer; picker UI pending |
| F01-N1 | Access/device failure | Deny/revoke camera/screen/mic; unplug device; actionable state and retained sources | Explicit OS/device acceptance | PENDING; no OS protections reset by agent |
| F02-H1 | Camera pause/resume/stop | Two ~5 s takes; pause returns, resume captures, stop releases device/player opens | Camera diagnostic | PASS; pause 0.150480 s, stop 0.266028 s |
| F02-E1 | Preview toggle during capture | Actual AppModel action enable/hide/re-enable; frames after enable, recording continues while hidden | Camera diagnostic regression | PASS after BUG-003; first test failed before repair |
| F02-E2 | Screen/audio continuity | Repeated pause/resume, very short takes, stream changes; no unintended gap/audio failure | Explicit hardware session | PENDING |
| F02-E3 | Double actions/cancellation | Trigger incompatible transitions, cancel countdown/save; no duplicate publication | Phase guards inspected; deadline/export core tests | PASS for cancellation/late completion; full rapid-action UI pending |
| F02-N1 | Mid-capture disruption | Sleep/lock, display/window loss, device unplug, permission revoked | Explicit hardware session | PENDING |
| F03-H1 | Local finalization | Generated red/blue takes; ordered frames/duration/audio; originals unchanged | Core media tests | PASS |
| F03-H2 | Camera media | Validate actual MP4, no audio, decode one frame either side of join, native playback advances | Camera diagnostic, pixels kept local | PASS |
| F03-E1 | Hung/late workers | Missing/noncooperative callback, cancellation, worker released after cancelled export | AsyncDeadline/ExportRunner regression tests | PASS; no late output promotion |
| F03-E2 | Recovery checkpoints | Missing checkpoint after completed source, existing output, missing camera, cancel | RecordingFinalizer tests | PASS with generated media; existing ready output retained |
| F03-E3 | Storage boundaries | Linked/remote/nonlocal paths, corrupt session, file permissions, title path isolation | Library/path tests | PASS |
| F03-N1 | Interrupted disk writes | Abrupt kill, disk full/low disk, unfinalized source; finished files preserved, no false-ready state | Explicit fault/device session | PENDING; MOV fragments are not proof of complete crash recovery |
| F03-E4 | Long-session efficiency | 30–60 min capture, pause cycles, stop; frame/drop/sync/memory/energy/disk metrics | Explicit benchmark, isolated local sample | PENDING; no performance claim |
| F04-H1 | Player/search/notes | Generated demo → mounted playback → metadata search → note add/remove | Studio diagnostic | PASS |
| F04-H2 | Transcript review/export | Sample text timestamps, correction, SRT/VTT/Markdown export and escaping | Core tests + studio diagnostic | PASS; sample transcript only |
| F04-H3 | Actual recognition | Installed language, explicit local speech sample; timed recognition and cancellation | Explicit local speech session | PENDING |
| F04-N1 | Unavailable speech assets | Missing installed language; fail locally without downloader/server fallback | Availability logic inspected | PENDING OS-level acceptance |
| F04-E1 | Input/accessibility | Empty/no-result, Unicode/long notes, keyboard seek/VoiceOver reading order | Core metadata/path checks plus full native walkthrough | PARTIAL; full native acceptance pending |
| F05-H1 | Trim | Generated clip → range 1–3 s → 2 s separate output → busy flag clears | Core tests + studio diagnostic | PASS |
| F05-H2 | Timed visual export | Drawing/zoom cue → preview/render/export; frames only change inside cue | Core frame checks + studio diagnostic | PASS |
| F05-E1 | Export failure/cancel | Invalid range, existing destination, cancellation/late completion; originals unchanged | Core tests | PASS |
| F05-E2 | Complex edits | Many cues/long media/cancel; stable preview, storage/memory bounds | Extended generated benchmark | PENDING |
| F06-H1 | Floating panels retained | Show → move programmatically → hide/show → close/reopen studio → same state | Studio diagnostic | PASS configuration/programmatic scope |
| F06-H2 | Native visible controls | Inspect capsule/menu; close main window; Open studio restores generated review | Native CUA | PASS |
| F06-E1 | Real drag/Spaces/fullscreen | Drag with pointer; other apps, multiple displays/Spaces/fullscreen; no unwanted activation | Native CUA/manual | PENDING; lone-panel coordinate automation returned noWindowsAvailable |
| F06-N1 | Display privacy | Record generated display/window and prove studio/HUD absent from resulting frames | Explicit screen acceptance | PENDING; source filter inspected only |
| P01 | Runtime local-only boundary | Strict codesign, signed entitlement/source audit; same-entitlement no-payload loopback probe denied | `verify.sh` | PASS; no external host or recording sent |
| P02 | Native compatibility | Minimum macOS 15.2, Intel, reduced transparency/contrast, distribution signing | Separate OS/hardware/release environment | PENDING |

Retained automated coverage: 35 core tests in 6 suites, a nine-check generated studio workflow with 14 layout images, and the explicit camera lifecycle regression. These have different scopes and are not one combined end-to-end reliability count. Re-run generated verification after a repair batch, and device cases when affected capture/device behavior changes. Never substitute demo output for real capture acceptance.

Release gate: complete F01-H3/H4/N1, F02-E2/N1, F03-N1/E4, F06-E1/N1 and relevant compatibility/accessibility checks, with metadata-only evidence and no unresolved reproduced S1/S2. Keep all media/process samples/container inventory private. Only copy allowlisted generated fixture images to the repository.

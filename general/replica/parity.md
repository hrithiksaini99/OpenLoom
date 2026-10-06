# Loom local workflow parity — development checkpoint

Generated with Replica's inspected `parity.py` on 6 October 2026 from [features.csv](features.csv). Weights: must 3, should 2, could 1; partial receives half credit. Eight cloud exclusions and three local product additions are not scored. Additions describe our explicit boundaries, not proof that Loom has no internal recovery mechanisms. `partial` includes a must-have acceptance gap even where capture code exists.

**Layout score: unavailable.** No original/clone pair at the same viewport/state was obtained; the browser connector denied the original page. No diff image or combined visual score is claimed. Our generated layout fixtures and native UI were inspected independently. Behavior comparison and the top five priorities are in [plan.md](plan.md); detailed evidence is in [test-plan.md](test-plan.md).

**Verdict: development source may be published; the application is not ready for a dependable public release.** Seven must-haves are partial. The reproduced camera failures are repaired, but real screen/audio, interruption and long-session acceptance remain. Feature coverage is neither a performance measurement nor a stability probability.

## Parity: 51.9 / 100

features 51.9  (37 counted, must-haves 5 of 12 done)

Not shippable yet: 7 must-have features are not done.

## By area, weakest first
- local intelligence             0.0  (2 features)
- recording                     37.0  (12 features)
- capture                       52.1  (10 features)
- editing                       57.1  (7 features)
- review                        84.6  (6 features)

## Missing, in build order
- [must] capture: Display or window capture, partial  (F01; ScreenCaptureKit implemented; actual source picker/start/pause/stop/display exclusions awaiting screen acceptance)
- [must] capture: Microphone input, partial  (F01; default device implemented; actual microphone acceptance unrun)
- [must] capture: Screen plus camera capture, partial  (F01/F02; generated composition and private camera checked separately; live screen/camera synchronization unverified)
- [must] recording: Draggable resizable camera bubble, partial  (S03; native preview panel and three sizes implemented; physical drag unverified; encoded bubble still uses presets)
- [must] recording: Floating recording controls, partial  (S02/F06; native capsule/menu and close/reopen verified; physical drag and cross-Space/fullscreen acceptance pending)
- [must] recording: Pause and resume, partial  (F02; real camera passed; screen/audio continuity and repeated long-session cycles unverified)
- [must] recording: Reliable stop and reviewable video, partial  (F03; bounded finalization and raw take recovery implemented; short camera passed; screen/audio/long takes pending)
- [should] capture: Audio level meters and preflight check, no  (S01/S02; cannot currently check signal level or hear a test sample in the app)
- [should] capture: Choose microphone device, no  (F01; input currently follows the macOS default)
- [should] capture: Custom region capture, no  (F01; display/window only)
- [should] editing: Blur sensitive content, no  (F05; redaction absent; do not treat drawing boxes as verified redaction)
- [should] editing: Cut and stitch multiple ranges, no  (F05; no general timeline or stitch editor)
- [should] recording: Live drawing while recording, no  (F02; drawing currently occurs after recording)
- [should] recording: Restart or discard a take, no  (F02; no quick restart/discard control; source preservation is deliberate)
- [should] recording: Speaker notes while recording, no  (F02; review notes exist; teleprompter/speaker-notes overlay absent)
- [should] recording: Toggle encoded camera while recording, no  (F02; preview visibility toggles safely; cannot enable/disable the recorded camera stream live)
- [should] capture: System audio input, partial  (F01; screen stream supports audio; real capture and heard playback unverified)
- [should] recording: Cursor and click highlights, partial  (F02/F05; cursor visibility and opt-in display-click events; post-recording highlight cues; multi-display mapping unverified)
- [should] recording: Recording keyboard shortcuts, partial  (S02/S09; app-scoped commands implemented; system-wide hotkeys and customization absent)
- [should] review: Transcripts and captions, partial  (S05; installed on-device SpeechTranscriber implementation; sample exports pass; real speech recognition unrun)
- [could] editing: Remove filler words and silence, no  (F05; no text-driven cut pipeline)
- [could] editing: Stylized playback captions, no  (S05; standard caption preview and SRT/VTT only; burned-in subtitles are a separate local roadmap item not established as a Loom feature)
- [could] local intelligence: Automatic titles summaries and chapters, no  (F04; manual notes/chapters only; future local model must be user supplied and explicitly enabled)
- [could] local intelligence: Filler correction with generated speech, no  (F05; no local text-to-speech edit pipeline)
- [could] recording: Camera frames and virtual backgrounds, no  (S03; original plain ring/gradient placeholder; no decorative frames/background removal)
- [could] review: Folders and tags, no  (S04; flat searchable library currently)

## Left out on purpose (not scored)
- Upload and hosted sharing links: Outside explicit local-only boundary; export a local file instead
- Remote comments and emoji reactions: No remote service; local timestamped notes cover personal review only
- Viewer analytics and engagement: Requires remote viewer activity; excluded
- Accounts teams and permissions: Single OS user; private sandbox storage
- Cloud AI and meeting bots: No networked inference or automated remote meeting attendance
- Cloud app integrations and embeds: No external sharing API or integrations
- Hosted personalized call-to-action buttons: Interactive hosted playback outside local file scope
- Automatic uploads after recording: Runtime has no network entitlement or uploader

## Yours, not in the original (not scored)
- OS sandbox rejects network connections
- Private raw takes retained for local recovery
- Generated demo without device permissions

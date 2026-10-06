# Loom comparison using Replica

Reviewed 6 October 2026 against OpenLoom 0.4.0 (build 5). Scope: a native macOS, single-user, local-only walkthrough recorder and review/editor. The user authorized publishing source, documentation and generated UI fixtures, never recordings.

Applied [Replica](https://github.com/Jakeschincariol/replica-skill)'s `replica-recon`, `replica-architect`, `replica-design`, `replica-test` and `replica-diff` modules. Their templates were adapted to SwiftUI/AppKit, local manifests and installed-app checks. A web server, hosted database, authentication, Tailwind and Playwright would not serve this product. The downloaded skill lives in ignored `.build/replica-skills`; it is not an app dependency.

Read these in order:

1. [Comparison and next build plan](plan.md): practical differences, top five priorities and acceptance gates.
2. [Recon](recon.md): primary sources, screens, flows and evidence limits.
3. [Feature matrix](features.csv) and [computed parity](parity.md): implemented, partial, missing and intentionally excluded behavior.
4. [Architecture](architecture.md), [design system](design/components.md) and [tokens](design/tokens.json).
5. [Test plan](test-plan.md), [reproduced bugs](bugs.md) and [metadata-only acceptance evidence](../macos/Validation/acceptance-2026-10-06.json).

This is a development checkpoint, not a Loom-equivalent release. The feature score is a planning aid, not a reliability, performance or visual similarity benchmark. `yes` means the implementation covers the documented feature; a note distinguishes inspected code, generated tests and real-device evidence. `partial` also covers an essential acceptance gap. Cloud features are explicitly excluded from the denominator.

The browser connector denied access to Atlassian's site during this review. Existing official documentation was available, but no matched original/clone screenshot pair was obtained. Consequently there is no numeric layout score and no claim of a measured Loom visual match. [Clone screenshots](clone-screens/) contain only generated app-owned fixtures. Glass and AppKit video surfaces do not fully render in those fixtures; the visible native capsule and generated playback were checked separately. Loom assets, screenshots, code and private APIs are not distributed.

Replica's inspected standard-library tools produced the feature and static contrast reports locally:

```bash
python3 .build/replica-skills/replica-diff/parity.py general/replica/features.csv --markdown
python3 .build/replica-skills/replica-design/contrast.py general/replica/design/tokens.json
```

The helpers can be obtained from the linked skill repository. Record the inspected helper hashes from the acceptance evidence when reproducing this checkpoint. Do not apply `imgdiff.py` to different viewports/states or unrelated public marketing images.

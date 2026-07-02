# Contributing to RunCockpit

## Building

```bash
scripts/build-local.sh
```

Produces `build/RunCockpit.app`, ad-hoc signed — no Apple Developer account required. Or open `RunCockpit.xcodeproj` in Xcode 16+ and run.

## Project layout

See [FEATURES.md](FEATURES.md) for the full architecture, navigation routes, and domain model. Quick map:

```
RunCockpit/
├── RunCockpitApp.swift   # @main entry point
├── AppState.swift        # single @Observable state container
├── Views/                 # SwiftUI screens
├── Data/                  # file watching, caching, pricing, settings, session store
└── Model/                 # domain types + raw JSONL record decoding
```

## Ground rules

- **No new dependencies.** The app is pure SwiftUI + CoreServices — no SPM packages, no third-party libraries. Keep it that way.
- **Read-only towards `~/.claude/`.** RunCockpit must never write into the Claude Code data directory. All app state goes under `~/Library/Application Support/RunCockpit/`.
- **No network calls.** No analytics, no telemetry, no remote config. Anything the app needs must come from the local filesystem or be user-editable in Settings (like the pricing table).
- **i18n**: user-facing strings go through `tr()`/`t()` (see `RunCockpit/Data/Localization.swift`), not raw literals. Run `scripts/check-i18n.sh` before opening a PR — it flags un-localized French string literals reaching the UI.

## Submitting changes

1. Fork, branch, make your change.
2. Run `scripts/check-i18n.sh` and confirm the app builds (`scripts/build-local.sh`).
3. Open a PR describing what changed and why.

Bug reports and feature requests are welcome via GitHub Issues.

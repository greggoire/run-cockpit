# RunCockpit — Technical Reference

Native macOS app (SwiftUI, macOS 15+) that visualizes Claude Code sessions stored under `~/.claude/` in real time. Read-only — it never writes into that directory. Its own data (cache, pricing, preferences) lives under `~/Library/Application Support/RunCockpit/`.

---

## Overview

RunCockpit is a Claude Code session observer. It answers "what is Claude doing right now, and what has it cost?" without hand-parsing JSONL files.

**Primary use cases**
- Monitor active agents (busy vs. idle) at a glance
- Inspect the sub-agent graph of a complex session
- Track token cost per session, project, and model
- Get notified when an agent is waiting on human input
- Resume or terminate a session without opening a terminal

---

## Tech stack

| Layer | Technology |
|---|---|
| Language | Swift 5.9+ |
| UI | SwiftUI (macOS only, no AppKit views except `NSOpenPanel`) |
| State | `@Observable` (macOS 15 API) — a single `AppState` class |
| File watching | `FSEventStreamCreate` (CoreServices) — zero polling |
| Notifications | `UNUserNotificationCenter` |
| Persistence | JSON under `~/Library/Application Support/RunCockpit/` |
| Charts | Pure SwiftUI — no third-party library |
| External dependencies | None |
| Build | Xcode 16+, no SPM, no CocoaPods |
| Sandbox | Not sandboxed (free access to `~/.claude`) |

---

## Navigation

Five routes managed by the `AppState.Route` enum:

| Route | View | Sidebar label |
|---|---|---|
| `.active` | `ActiveDashboardView` | Active Sessions |
| `.stats` | `StatsView` | Statistics |
| `.history` | `HistoryView` | History |
| `.pricing` | `PricingView` | Pricing |
| `.detail` | `SessionDetailView` | (not in sidebar — reached by clicking a card) |

---

## Screens and features

### 1. Active Dashboard (`ActiveDashboardView`)

Two real-time columns:
- **"Waiting on you"** — idle sessions, agent waiting for user input
- **"Running"** — busy sessions, agent currently working

Each card (`SessionCardView`) shows:
- Session title, project path, git branch
- Model, tokens consumed, estimated cost
- Number of active sub-agents, elapsed time, relative last-activity timestamp

Actions available on each card:
- **Terminate** — sends SIGTERM (with confirmation dialog)
- **Resume** — generates a `.command` script and opens it in Terminal (`claude --resume <id>`)
- **Click** → navigate to session detail

### 2. Statistics (`StatsView`)

Aggregated analytics dashboard. Filters: period (7 / 30 / 90 days / all), project, model.

Sections:
- **4 KPIs**: total cost (+ % change vs. previous period), tokens (+ average/session), sessions (+ rate/day), sub-agents spawned (+ rate/session)
- **Bar chart**: cost per day
- **Token breakdown**: stacked bars per bucket (input, output, cache write 5m, cache write 1h, cache read)
- **Cost by model**: ranked bar chart
- **Cost by project**: ranked, scrollable bar chart
- **Top 5 most expensive sessions** (clickable → detail)

### 3. History (`HistoryView`)

Tabular list of terminated sessions. Columns: status, title, model, project, branch, date, duration, tokens, cost, agents, turns.

Controls:
- **Period filter**: segmented control 7/30/90/all
- **Text search**: filters on title, path, branch, model

Click a row → session detail.

### 4. Session Detail (`SessionDetailView`)

Main inspection screen. Layout:
- **Header**: status, title, project/branch, buttons (Resume, Finder, IDE, Copy ID)
- **Stats strip**: tokens, cost, duration, turns, agent count
- **Left panel**: agent graph + tabs (Timeline / Action Flux)
- **Right panel** (fixed 344pt): inspector for the selected node

### 5. Agent Graph (`AgentGraphView`)

Tree visualization of agents and sub-agents, hand-drawn on a SwiftUI `Canvas`:
- Nodes = `NodeCard` (type, model, tokens, cost)
- Edges = Bézier curves, parent → child
- Clicking a node updates the Inspector and the Flux view

### 6. Inspector (`InspectorView`)

Right panel of the detail screen, for the selected node:
- Type / model / status tags
- 5-bucket token breakdown
- Estimated cost (or a "missing price" badge for an unknown model)
- Timings: start / end / duration
- Tool counters: read, bash, edit, search, lines +/-
- Task prompt / description

### 7. Action Flux (`FluxView`)

Ordered stream of an agent's actions:
- **Reasoning blocks** (assistant text, diamond bullet)
- **Tool calls** (circle bullet, colored by tool type): name, input summary, running/error badge, duration, timestamp, tokens, result preview

### 8. Timeline (`TimelineView`)

Session lifecycle events, in chronological order:
- Session start
- Sub-agent spawns (type + label)
- Sub-agent completions (+ duration)
- Still-active agents (pulsing dot)

### 9. Pricing (`PricingView`)

Editable per-model pricing table in $/M tokens. Columns: input, output, cache write 5m, cache write 1h, cache read.

- Each cell is a numeric `TextField` that saves and instantly recalculates every displayed cost
- "Reset to defaults" button restores the built-in values
- Persisted to `~/Library/Application Support/RunCockpit/pricing.json`
- 13 models covered, from `claude-haiku-3-5` to `claude-fable-5` / `claude-mythos-5`

---

## Data sources

Everything is read from the local filesystem — no network calls.

| Source | Path | Content |
|---|---|---|
| Live session registry | `~/.claude/sessions/<PID>.json` | PID, sessionId, cwd, status, startedAt, name |
| Session transcripts | `~/.claude/projects/<hash>/<sessionId>.jsonl` | Messages, tool calls, tokens, timestamps, git branch, title |
| Sub-agent transcripts | `~/.claude/projects/<hash>/<sessionId>/subagents/agent-<id>.jsonl` | Tokens and actions per agent |
| Sub-agent metadata | `~/.claude/projects/<hash>/<sessionId>/subagents/agent-<id>.meta.json` | Type, description, depth |

Files written by the app:

| File | Purpose |
|---|---|
| `~/Library/Application Support/RunCockpit/settings.json` | Appearance, notifications, editor path |
| `~/Library/Application Support/RunCockpit/pricing.json` | Pricing table |
| `~/Library/Application Support/RunCockpit/history-cache.json` | History cache, invalidated by mtime |

---

## Key domain entities

| Entity | Description |
|---|---|
| `SessionSummary` | Lightweight session view (id, status, title, project, branch, model, tokens, cost, agents) |
| `SessionDetail` | Full view: `SessionSummary` + agent tree + timeline |
| `AgentNode` | An agent or sub-agent: id, parent, type, model, status, tokens, tools, prompt, actions |
| `ActionEvent` | One action in an agent's flux: reasoning text or a tool call |
| `TimelineEvent` | Lifecycle event (start / spawn / done / active) |
| `TokenBuckets` | 5 counters: input, output, cacheWrite5m, cacheWrite1h, cacheRead |
| `PricingProfile` | $/M token pricing for a model (5 buckets) |
| `AppSettings` | Appearance (dark/light), notifications enabled, IDE editor path |

---

## System behaviors

| Behavior | Mechanism |
|---|---|
| Real-time updates | `FSEventStream` on `~/.claude/sessions/` and `~/.claude/projects/`, debounced 400ms kernel + 250ms main queue |
| Liveness check | `kill(pid, 0)` on each session's PID |
| Notifications | `UNUserNotificationCenter` — "session waiting" banner on `busy → idle` transition; tap opens the detail view |
| History cache | JSON dict keyed by mtime; avoids re-parsing unchanged JSONL files |
| Token deduplication | Token entries are deduplicated by `message.id` to avoid double-counting |
| Session-end detection | `stop_reason == "end_turn"` on the last assistant message |
| Finished-agent detection | Parses `<task-notification>` tags in queue-operation entries of the JSONL |

---

## Known limitations / roadmap

- Grouping projects by git remote URL (collapsing worktrees/clones of the same repo) is implemented and available as a toggle in Settings, but off by default.
- Localization currently covers English and French; `scripts/check-i18n.sh` guards against un-localized French string literals leaking into the UI.

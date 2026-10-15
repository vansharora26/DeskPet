# DeskPet 2.0

A pixel-art cat that lives on your Mac desktop — and helps you drink water,
focus, remember things, and get stuff done. Native Swift + SwiftUI + AppKit,
local-first, no dependencies. AI is optional.

## Run it

Requires macOS 14+ and Xcode **or** just the Command Line Tools (`xcode-select --install`).

```sh
scripts/build-app.sh          # builds build/DeskPet.app (release, ad-hoc signed)
open build/DeskPet.app
```

Checks:

```sh
scripts/test.sh                          # 71 unit tests (core logic + API client, offline)
.build/release/DeskPet --self-test       # 30 end-to-end app-layer checks in a temp folder
.build/release/DeskPet --export-previews ./previews   # renders every pet state to PNG
```

## What it does

| Area | Highlights |
| --- | --- |
| **Pet** | Click to pet, drag to move, right-click for the full menu. Moods tied to real state: *focused* (headband while a focus timer runs), *resting* (mug during breaks), *thirsty* (when a water reminder is showing), *celebrating* (goal reached, session done, level up), *sleepy*, *happy*. Size, light/dark appearance, coats & accessories. |
| **Hover bar** | Water · Focus · Chat · Capture · More. A focus countdown badge sits under the cat while a timer runs. |
| **Hydration** | One-click logging, editable servings & goal, undo, history, daily/weekly summaries, reminders with snooze/dismiss/done, quiet hours, pause-after-goal. |
| **Focus** | Start/pause/resume/skip/reset, short & long breaks, auto-start options, history, daily goal, movement & eye-rest reminders, mute nonessential reminders while focusing. |
| **Capture, tasks & notes** | ⌃⌥N capture (Return saves; ⌘T makes it a task; “tomorrow 5pm” becomes the deadline). Inbox / Today / Upcoming / Completed, search, edit, pin, deadlines, reminders, soft delete with undo + Recently Deleted. |
| **Launcher** | ⌃⌥Space. Natural language (“water 250 ml”, “focus for 30 minutes”, “remind me to call Sam at 7 pm”), live suggestions, shows exactly what will run, confirms risky actions, Undo. |
| **Chat** | Real Claude assistant with typed tools (log water, timers, tasks, notes, reminders, stats). Local commands work without AI. |
| **Today** | Daily briefing (tasks, deadlines, water, focus, one suggested next step) and an end-of-day wrap-up. |
| **Stats** | 7-day charts, breaks, task completion, and rule-based insights that say how they were computed. |
| **Progression** | XP with daily caps, levels, unlockable coats/accessories, gentle milestones, optional streaks, fully disable-able. Missing a day never costs anything. |

### Global shortcuts (configurable in Settings › Shortcuts)

| Shortcut | Action |
| --- | --- |
| ⌃⌥Space | Command launcher |
| ⌃⌥N | Quick capture |
| ⌃⌥C | Chat |
| ⌃⌥W | Log a glass of water |
| ⌃⌥H | Show / hide pet |
| ⌃⌥P | Keyboard mode (arrows move the pet, Space pets, W water, F focus, Esc exits) |

Shortcuts use Carbon `RegisterEventHotKey`: only these combinations are
delivered to DeskPet. There's no keyboard monitoring and no Accessibility
permission.

## AI setup (optional)

DeskPet works fully without AI. To enable the assistant:

**Development (your own key):** Settings › AI › paste an Anthropic API key
(console.anthropic.com). The key is stored only in your **macOS Keychain** —
never in source, the app bundle, UserDefaults, logs or data files. Requests go
directly from your Mac to `api.anthropic.com`. Security limitation: anyone with
access to your unlocked user account could read the key from the Keychain, and
API usage is billed to that key.

**Production (no key in the app):** run a backend that holds the key and set
Settings › AI › *Backend proxy URL*. DeskPet then sends requests without any
credential. `tools/dev-proxy.py` is a minimal reference (stdlib Python,
localhost only, model allowlist, `max_tokens` cap, no body logging):

```sh
export ANTHROPIC_API_KEY=sk-ant-...
python3 tools/dev-proxy.py      # then use http://127.0.0.1:8787/v1/messages
```

A real deployment must also authenticate users and rate-limit per user;
otherwise the endpoint is an open relay for your credit.

**Model:** Claude Opus 5 by default (Sonnet 5 / Haiku 4.5 selectable). With
Opus 5, DeskPet opts into the API's server-side refusal fallback
(`fallbacks: "default"`), so a declined request is retried on a suitable model.

### What is sent to the AI

* The messages you type in Chat (or explicitly send from the launcher), your
  pet's name, and your local time (to resolve “at 7 pm”).
* Your tasks, notes or stats **only** when the assistant asks through a read
  tool and your setting allows it: *Ask each time* (default), *Always*, or
  *Never*.
* Never: clipboard, screen, files, keystrokes, or anything in the background.
  Recognised commands (“log 300 ml”) run on your Mac and aren't sent at all.

The assistant can act only through a fixed set of typed tools. Every argument is
validated (types, ranges, dates in the future…). Stopping a timer or turning
reminders off asks for confirmation. There is no shell, file or network access
for the model.

## Privacy & data

Everything lives in `~/Library/Application Support/DeskPet/`:
`deskpet-data.json` (habits, notes, tasks, progress), `pet.json`, `chat.json`.
Preferences are stored in the `app.deskpet.DeskPet` defaults domain, and the
API key in the Keychain. Settings › Privacy & Data can **export** everything
(JSON + CSV for water, focus, notes & tasks) or **delete** it all. There are no
analytics, no accounts, and no network requests unless you use AI chat.

Hydration goals are personal settings, not medical advice. DeskPet only knows
what you log, and it has no calendar access.

## Architecture

```
Sources/DeskPetCore/      Pure, unit-tested logic (no UI)
  Hydration · Reminders (single next-due planner) · Focus (absolute-time timer)
  Items (notes/tasks) · NaturalDate + Commands (NL → typed AppCommand)
  Progression · Insights & Briefing · DeskPetData (versioned, tolerant JSON)
  DataExport (JSON/CSV) · JSONValue + ClaudeClient (Messages API, retries)
  PetStats/PetEngine/PetStore (pet needs, from 1.0)
Sources/DeskPet/
  App/        AppDelegate (composition root), AppModel (source of truth + events),
              CommandExecutor (the one place commands run), ReminderScheduler,
              NotificationManager, HotKeyManager, PetMenu, StatusBarController, SelfTest
  AI/         ChatModel (local-first routing, tool loop, permissions), AssistantTools, Keychain
  Pet/        PetViewModel, PetBehavior (events → expressions), PetCallout, Speech, Sound
  Rendering/  Pixel sprites → cached bitmaps, PetAnimator, PetAnimationDriver
  Window/     Pet panel (click-through, keyboard mode), layout, WindowRouter
  Hub/        Today · Chat · Water · Focus · Tasks & Notes · Stats
  Views/      Pet scene, Quick Capture, Launcher, Settings, Welcome
  Design/     Design tokens & shared components
```

Reliability notes:

* **Timers:** the focus timer stores `endsAt`/remaining, never a counter. A
  one-shot timer fires at the exact end (App Nap is held off only while a
  session runs). It's correct after sleep, hiding, or relaunch. If the app was
  closed past the end, the session is recorded at its true end time.
* **Reminders:** the next due time is recomputed from saved state, and one
  timer runs to the earliest. Notifications use one fixed ID per kind, so
  duplicates can't accumulate.
* **Days:** “today” is always derived from the local calendar, so totals reset
  at local midnight and on time-zone changes.

## Known limitations

* Ad-hoc signed, not notarized. Other Macs will show a Gatekeeper warning until
  the app is signed with a Developer ID.
* macOS notifications and Open at Login require running the
  `.app` (not `swift run`). In-pet reminders always work.
* Reminders only fire while DeskPet is running.
* No calendar integration yet (planned as optional and read-only).
* AI chat responses aren't streamed; a typing indicator shows while waiting.

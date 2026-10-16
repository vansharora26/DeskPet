# DeskPet 2.1

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
scripts/test.sh                          # 85 unit tests (core logic, conversation, speech text, API client — offline)
.build/release/DeskPet --self-test       # end-to-end app-layer checks (chat, actions, voice, TTS) in a temp folder
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
| **Voice conversation** | “Talk to <pet>” window (pet’s Chat button, ⌃⌥C, or menu). Push-to-talk (hold the mic or ⌃⌥V; tap to latch), spoken replies with native macOS voices, listening / thinking / speaking animations, mute, interruption, short-term context. |
| **Today** | Daily briefing (tasks, deadlines, water, focus, one suggested next step) and an end-of-day wrap-up. |
| **Stats** | 7-day charts, breaks, task completion, and rule-based insights that say how they were computed. |
| **Progression** | XP with daily caps, levels, unlockable coats/accessories, gentle milestones, optional streaks, fully disable-able. Missing a day never costs anything. |

### Global shortcuts (configurable in Settings › Shortcuts)

| Shortcut | Action |
| --- | --- |
| ⌃⌥Space | Command launcher |
| ⌃⌥N | Quick capture |
| ⌃⌥C | Talk to your pet (conversation window) |
| ⌃⌥V (hold) | Push to talk from anywhere |
| ⌃⌥W | Log a glass of water |
| ⌃⌥H | Show / hide pet |
| ⌃⌥P | Keyboard mode (arrows move the pet, Space pets, W water, F focus, Esc exits) |

Shortcuts use Carbon `RegisterEventHotKey`: only these combinations are
delivered to DeskPet. There's no keyboard monitoring and no Accessibility
permission.

## Voice conversation

Open **Talk to <pet>** and either type or hold the mic button (or hold ⌃⌥V
from any app), speak, and release. A quick tap latches the mic until you tap
again.

* **Real actions, confirmed after they happen.** “I’ve had 300 ml of water”,
  “What’s my total?”, “Start a 25-minute focus session”, “another one”, “undo
  that”, “how long is left?” run on-device through the same validated commands
  as the rest of the app. The pet answers from the *result* (“Logged 300 ml…”),
  so a failed action is never announced as done. Other drinks (“300 ml of
  coffee”) are deliberately not logged as water.
* **Short-term context.** The conversation remembers the current topic and
  your last amount for 5 minutes (so “what’s my total?” follows what you were
  just doing), and starts fresh after 30 minutes of silence.
* **Microphone.** Off unless you’re holding the button or shortcut (or have
  tapped to latch it on). It turns off automatically after 60 seconds, when the
  window closes, or when the Mac sleeps. macOS shows its own mic indicator
  whenever it’s on. Permission is requested the first time you press the
  button, never at launch.
* **Privacy.** Speech recognition is **on-device only** by default (Settings ›
  Voice). If your language isn’t supported on-device, voice input stays off
  unless you explicitly allow Apple’s server recognition. Recordings are never
  stored.
* **Spoken replies.** Native `AVSpeechSynthesizer` voices (best installed
  quality, never novelty voices). Choose when to speak: when you talk to it
  (default), always, or never. Mute is in the window header. Speech stops the
  moment you press the mic, send a message, press Stop, or hit Esc. Replies are
  cleaned for listening: no emoji or markdown, units read as words, and long
  answers are trimmed (the full text stays on screen).
* **Text-only fallback.** Everything works by typing. If permission is
  denied, there’s no mic, or you run without the app bundle (`swift run`), the
  mic button explains why and chat continues as text.
* **AI.** With AI configured, open-ended questions go to Claude with a hint to
  answer in 1–2 spoken sentences. It can still act only through the typed,
  validated tools: no shell, no files, and confirmation for risky actions.
  On-device replies are spoken as-is.

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

* The messages you type or say in Chat (or explicitly send from the
  launcher) once transcribed to text, your pet's name, and your local time (to
  resolve “at 7 pm”). Audio is never sent to the AI. A one-line recap of
  actions you just did on-device in the same conversation (e.g. “logged 300
  ml”) is included for context, unless data sharing is set to *Never*.
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
  ConversationContext (short-term follow-ups) · SpokenText (text → speech-friendly)
  Progression · Insights & Briefing · DeskPetData (versioned, tolerant JSON)
  DataExport (JSON/CSV) · JSONValue + ClaudeClient (Messages API, retries)
  PetStats/PetEngine/PetStore (pet needs, from 1.0)
Sources/DeskPet/
  App/        AppDelegate (composition root), AppModel (source of truth + events),
              CommandExecutor (the one place commands run), ReminderScheduler,
              NotificationManager, HotKeyManager, PetMenu, StatusBarController, SelfTest
  AI/         ChatModel (local-first routing, context follow-ups, undo, tool loop, permissions), AssistantTools, Keychain
  Voice/      SpeechRecognizerService (push-to-talk, on-device), SpeechSynthesizerService, VoiceController
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
* Voice needs the `.app` bundle (it declares the microphone and speech
  recognition usage). On-device recognition depends on the language and Mac.
* The speech-to-text round-trip self-test runs only after you've granted Speech
  Recognition access in the app once. It's skipped otherwise, so tests never
  trigger permission prompts.

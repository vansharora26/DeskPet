# DeskPet 2.4

A cartoon cat that lives on your Mac desktop — and helps you drink water,
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
scripts/test.sh                          # 153 unit tests (core logic, Focus Worlds, roaming, distraction guard, meetings, Mac tools, conversation, speech text, API + license clients — offline)
.build/release/DeskPet --self-test       # end-to-end app-layer checks (chat, voice, Focus Worlds, audio, license gates, quick capture, text recognition, keep awake, clipboard, every PDF tool on real files, battery) in a temp folder
.build/release/DeskPet --export-worlds ./shots          # renders every Focus Worlds screen to PNG (offscreen)
.build/release/DeskPet --worlds-probe deepFocus 15      # runs a live world off-screen so you can measure CPU
.build/release/DeskPet --export-previews ./previews   # renders pet states, battery moods, every coat, accessory and eye colour to PNG
.build/release/DeskPet --export-spread ./spread       # renders the hover spread and the PDF Tools window to PNG
```

### Releasing

`scripts/release.sh` builds, signs with a Developer ID (hardened runtime),
notarizes with Apple, staples the ticket, and writes `dist/DeskPet-<version>.zip`.
The version comes from `VERSION` in `scripts/build-app.sh`. One-time setup:

1. Install a **Developer ID Application** certificate (plus Apple's
   *Developer ID Certification Authority G2* intermediate) in your login keychain.
2. Save notary credentials (prompts for an app-specific password):
   `xcrun notarytool store-credentials DeskPet-notary --apple-id <you@example.com> --team-id <TEAMID>`

The script checks both before building. If the network drops while Apple is
processing, it keeps retrying the same submission rather than re-uploading.

## What it does

| Area | Highlights |
| --- | --- |
| **Pet** | Click to pet, drag to move, right-click for the full menu. Moods tied to real state: *focused* (headband while a focus timer runs), *resting* (mug during breaks), *thirsty* (when a water reminder is showing), *celebrating* (goal reached, session done, level up), *sleepy*, *happy*. Size, light/dark appearance. Drawn with smooth vector shapes, so it's crisp at any size. |
| **Wardrobe** | 12 coats (tabby, solid, tuxedo, calico and Siamese markings, plus pastel colours), 7 eye colours including odd-eyed, and 11 accessories. |
| **Roaming** | The pet strolls along the bottom of the screen, hops onto the tops of other windows (and rides along when they move), chases the cursor now and then, and naps when you're away. Holds still while you hover, drag, focus, talk or have a reminder open. Reads window positions only. |
| **Distraction guard** | During focus sessions, a gentle nudge when a distracting app or site is in front for 10+ seconds, at most every few minutes, with "Hide app" and "5 more min". Sites work in Safari and Chromium browsers (asks for Automation permission once). Off by default. |
| **Calendar heads-up** | Optional, read-only access to macOS Calendar: a bubble a few minutes before each meeting (with a Join button for Zoom/Meet/Teams links, and Pause focus if a session is running), plus today's schedule in Today and the briefing. Off by default. |
| **Mac Tools** | **Screenshots** (⌃⌥S, or the camera on the hover bar): drag an area, Space for a window, or full screen from the menu. Copied to the clipboard and saved to Pictures › DeskPet Screenshots, with a corner preview you can click, drag into any app, or turn into text. **Copy text from screen** (⌃⌥T): drag over anything and the text goes to your clipboard, recognised on-device, with "Save as note". **Clipboard history** (⌃⌥B): the last 30 text copies, searchable, ↩ to copy back (or paste straight in with Accessibility permission); skips password-manager copies; off until you turn it on. **Keep awake**: 30 min, 1 h, 2 h or until off; the cat wears sunglasses meanwhile. Also in the launcher: "screenshot", "copy text from screen", "keep awake for 2 hours", "let my mac sleep". |
| **PDF tools** | A PDF Tools window (from the cat's spread, Mac Tools menu, launcher — "merge pdfs", "word to pdf", "compress pdf" — or by **dropping files on the cat**): Word/RTF/OpenDocument/HTML/text → PDF, merge PDFs and images (reorderable), images → PDF (A4, fitted), split or extract pages ("1-3, 5, 8-"), compress (keeps whichever of PDFKit or macOS's Reduce File Size filter wins), rotate all or some pages, add or remove a password, PDF → PNG pages, PDF → text (saved and copied). Results are saved next to the original with a clear suffix and never overwrite anything. All on-device with PDFKit. |
| **Battery moods** | On MacBooks the cat reacts to the battery: at 20% or less it gets sad and lazy (droopy ears, worried brows, heavy eyelids, slouching, lazy tail, yawns, slow trudging walks, fewer jumps); at 10% or less it's exhausted, mostly stays put, nods off and shows a blinking red battery. Plugging in perks it up with a ⚡ and a thank-you; it says when it's full. The menu shows the level. Can be turned off in Settings › General. |
| **Hover spread** | Hover the cat and nine labelled buttons spring out from behind it into two columns (one column near a screen edge): Log water · Start/pause focus · Focus World · Chat · New note · Screenshot · Copy text · PDF tools · More…. They tuck back in when you move away. A focus countdown badge sits under the cat while a timer runs. |
| **Hydration** | One-click logging, editable servings & goal, undo, history, daily/weekly summaries, reminders with snooze/dismiss/done, quiet hours, pause-after-goal. |
| **Focus** | Start/pause/resume/skip/reset, short & long breaks, auto-start options, history, daily goal, movement & eye-rest reminders, mute nonessential reminders while focusing. |
| **Capture, tasks & notes** | ⌃⌥N capture (Return saves; ⌘T makes it a task; “tomorrow 5pm” becomes the deadline). Inbox / Today / Upcoming / Completed, search, edit, pin, deadlines, reminders, soft delete with undo + Recently Deleted. |
| **Launcher** | ⌃⌥Space. Natural language (“water 250 ml”, “focus for 30 minutes”, “remind me to call Sam at 7 pm”), live suggestions, shows exactly what will run, confirms risky actions, Undo. |
| **Chat** | Real Claude assistant with typed tools (log water, timers, tasks, notes, reminders, stats). Local commands work without AI. |
| **Focus Worlds** | Immersive full-window environments: Deep Focus, Study, Work Sprint, Recharge, Daily Planning — each with its own scene, layout, type, pet behaviour and controls (⌃⌥F, the pet’s mountain button, menus, or Today). |
| **Voice conversation** | “Talk to <pet>” window (pet’s Chat button, ⌃⌥C, or menu). Push-to-talk (hold the mic or ⌃⌥V; tap to latch), spoken replies with native macOS voices, listening / thinking / speaking animations, mute, interruption, short-term context. |
| **Today** | Daily briefing (tasks, deadlines, water, focus, one suggested next step) and an end-of-day wrap-up. |
| **Stats** | 7-day charts, breaks, task completion, and rule-based insights that say how they were computed. |
| **Progression** | XP with daily caps, levels, unlockable coats/accessories, gentle milestones, optional streaks, fully disable-able. Missing a day never costs anything. |

### Global shortcuts (configurable in Settings › Shortcuts)

| Shortcut | Action |
| --- | --- |
| ⌃⌥Space | Command launcher |
| ⌃⌥N | Quick capture (new note or task) |
| ⌃⌥S | Screenshot (area) |
| ⌃⌥T | Copy text from screen |
| ⌃⌥B | Clipboard history |
| ⌃⌥C | Talk to your pet (conversation window) |
| ⌃⌥V (hold) | Push to talk from anywhere |
| ⌃⌥F | Enter / exit Focus Worlds |
| ⌃⌥W | Log a glass of water |
| ⌃⌥H | Show / hide pet |
| ⌃⌥P | Keyboard mode (arrows move the pet, Space pets, W water, F focus, Esc exits) |

Shortcuts use Carbon `RegisterEventHotKey`: only these combinations are
delivered to DeskPet. There's no keyboard monitoring and no Accessibility
permission.

## Focus Worlds

Enter from the pet’s **mountain** button, the pet or menu-bar menu, the
**Enter Focus World** banner on the Today page, the Focus tab, the launcher
(“enter focus world”), or **⌃⌥F**. Focus Worlds opens a dedicated window sized
to your screen’s visible area; use the ⤢ button (or ⌃⌘F) for native full
screen. It changes only DeskPet’s own window — never your desktop or wallpaper.

| World | Composition | What you do there |
| --- | --- | --- |
| **Deep Focus** | Night forest with a lit cabin, ultra-light timer, top bar that fades while you work | One intention (or pick a task), big timer, pause/resume/end, capture thoughts (⌘N), optional rain/forest/room sound |
| **Study** | Warm study room; timer on the desk, a cream “notebook” panel | Study sprints and breaks, a checklist (can link real tasks), session notes (save to Notes), today’s sprint history |
| **Work Sprint** | Crisp light grid, bold type, energetic pet in a headband | “What are you trying to finish?”, duration or finish-by time, milestones with progress, time spent, “I finished it!” |
| **Recharge** | Sunrise garden, relaxed pet | Short break countdown, optional breathing guide, rotating stretch/eye-rest suggestions, back to your previous world. No streaks or scores. |
| **Daily Planning** | Bright morning desk | Up to three outcomes (from your tasks, or new ones saved as tasks due today), available time → estimated sessions, notes, start a sprint on any priority, end-of-day review. No calendar access. |

**One timer.** Every world uses DeskPet’s existing focus timer (absolute end
times, restart-safe). Switching worlds never restarts a session; a second
competing timer can’t be started; a session runs on after you exit, and the
pet offers to take you back after a relaunch. World sessions are recorded in
the normal focus history with their world, label and optional reflection.
Finishing is recorded as *completed*; ending early as *ended early* (no
shaming); “Discard” records nothing. Each session is recorded exactly once.

**End of session.** A summary shows time completed, the intention, status,
an optional “What did you accomplish?”, a checkbox to complete the linked
task, and Start another / Take a break / Return to DeskPet (configurable).

**Reminders & notifications.** Water/movement reminders are held during
sessions if you choose (existing setting); reminders that do appear show
inside the world while the desktop pet is hidden. The optional end-of-session
macOS notification is scheduled once per session end, so it can’t duplicate.

**Ambient sound** (Deep Focus, Study, Recharge) is **off by default**. Rain,
forest breeze, soft room noise and fireplace are **synthesized live on your
Mac** — no recordings, downloads or licensing. One audio engine plays one
sound at a time (switching crossfades; nothing overlaps) and it fades out when
you leave the world or the summary appears.

**Performance & motion.** Scenes are drawn once; only small details (fireflies,
steam, petals, a light sweep) animate at 5–15 fps via a low-rate clock that
runs only while visible. Measured: about 2–5% CPU with a 1440×900 world
animating on “Subtle”, ~0% on “Still”. Motion follows Settings › Focus Worlds,
DeskPet’s Animations switch and macOS Reduce Motion.

**Settings › Focus Worlds:** open to the picker or a default world, per-world
durations, ambient sound (on/off, sound per world, volume), motion (Lively /
Subtle / Still), background (illustrated / minimal), pet in worlds, hide the
desktop pet, breathing guide, session-end behaviour, notification and
reminder holding. Shortcut in Settings › Shortcuts.

In-world keys: ⌘1–⌘5 switch worlds, ⌘0 world picker, ⌘⏎ start, ⌘P
pause/resume, ⌘N capture a thought, ⌘W exit.

**Adding worlds later.** A world is a `FocusWorld` case (title, timer phase,
durations, sounds) + a `WorldTheme` + a scene + one view; sessions, summary,
audio, pet behaviour and settings are shared. Nothing is paywalled.

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

**Connect your own Claude (most people):** Settings › AI › *Connect your Claude*
walks you through it: open the Claude Console (platform.claude.com), create an
API key, copy it, and click **Paste & Connect**. DeskPet checks the key's shape
(rejects Admin keys and stray spaces), saves it, and makes one tiny test call; a key
Anthropic rejects is removed again. Usage is billed by Anthropic to your Console
account, separately from any Claude Pro or Max plan, and "out of credits" errors
link straight to Console › Billing. The key is stored only in your **macOS
Keychain** — never in source, the app bundle, UserDefaults, logs or data files —
and Settings only ever shows its last four characters. Requests go directly from
your Mac to `api.anthropic.com`. Security limitation: anyone with access to your
unlocked user account could read the key from the Keychain.

**Company / team proxy (no key in the app):** run a backend that holds the key and set
Settings › AI › Advanced › *proxy URL*. DeskPet then sends requests without any
credential. `tools/dev-proxy.py` is a minimal reference (stdlib Python,
localhost only, model allowlist, `max_tokens` cap, no body logging):

```sh
export ANTHROPIC_API_KEY=sk-ant-...
python3 tools/dev-proxy.py      # then use http://127.0.0.1:8787/v1/messages
```

A real deployment must also authenticate users and rate-limit per user;
otherwise the endpoint is an open relay for your credit.

**Model:** Claude Opus 5.5 by default; Claude Sonnet 5.5 and Claude Haiku 5.5 are
selectable (older saved choices move to their successor automatically). Thinking
is left adaptive and `output_config.effort` is set to `medium` explicitly. With
Opus 5.5 and Sonnet 5.5, DeskPet opts into the API's server-side refusal fallback
(`fallbacks: "default"`), so a declined request is retried on a suitable model;
Haiku 5.5 has no server-side fallback, so a refusal shows a polite message.

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

## Trial & license (Dodo Payments)

DeskPet is free to try for **14 days** with everything unlocked. After that, the
pet, water tracking, the focus timer, notes, tasks and reminders stay **free
forever**; **Focus Worlds, AI chat, voice, roaming, the distraction guard and calendar heads-up** need a one-time license.

* **Buying:** "Buy DeskPet" opens `DPBuyURL` (default https://deskpet.app), whose
  button links to a Dodo Payments checkout. Dodo handles payment, tax and the
  receipt, and **emails the license key**.
* **Activating:** Settings › License → paste the key → Activate. DeskPet calls
  Dodo's public license endpoints (`/licenses/activate`, `/validate`,
  `/deactivate`); they need **no API key, so no secret ships in the app**. Sent:
  the key and this Mac's name. Stored: the key and activation ID, in the Keychain.
* **Checks:** re-validated about weekly; works offline for 30 days after the last
  successful check. A revoked or refunded key locks premium features again.
* **Moving Macs:** Settings › License → Deactivate frees the slot.
* **Environments:** `scripts/build-app.sh` builds accept Dodo **test** keys
  (`DESKPET_DODO_ENV=test_mode`); `scripts/release.sh` builds accept **live**
  keys. A test key never works in a live build.

Dodo setup: create the product (one-time price), add a **License Key**
entitlement (e.g. 3 activations), and put its payment link
(`https://checkout.dodopayments.com/buy/pdt_…`) behind the Buy button on the website.

## Privacy & data

Everything lives in `~/Library/Application Support/DeskPet/`:
`deskpet-data.json` (habits, notes, tasks, progress), `pet.json`, `chat.json`.
Preferences are stored in the `app.deskpet.DeskPet` defaults domain, and the
API key and license in the Keychain. Settings › Privacy & Data can **export** everything
(JSON + CSV for water, focus, notes & tasks) or **delete** it all (an activated
license is kept; deactivate it in Settings › License). There are no analytics and
no accounts. The only network requests are AI chats you send and, once you
activate a license key, a license check about once a week.

Optional permissions, each asked for only when you turn its feature on:
**Calendars** (calendar heads-up, read-only) and **Automation** for your browser
(distraction guard reads the current tab's address to compare with your list).
Also **Screen Recording** (screenshots and copy text from screen; images stay on your Mac
and text recognition runs on-device) and **Accessibility** (only if you turn on
"Paste right away" for clipboard history). Clipboard history is off by default; when on
it keeps the last 30 text copies in `clipboard.json` (readable only by you) and never
stores copies marked secret by password managers. "Delete all data" erases it.
Roaming reads other windows' positions only (no titles or contents).
None of this is stored or sent anywhere.

Hydration goals are personal settings, not medical advice. DeskPet only knows
what you log.

## Architecture

```
Sources/DeskPetCore/      Pure, unit-tested logic (no UI)
  Hydration · Reminders (single next-due planner) · Focus (absolute-time timer)
  Items (notes/tasks) · NaturalDate + Commands (NL → typed AppCommand)
  ConversationContext (short-term follow-ups) · SpokenText (text → speech-friendly)
  FocusWorlds (worlds, settings, sprint/study/day plans)
  Progression · Insights & Briefing · DeskPetData (versioned, tolerant JSON)
  DataExport (JSON/CSV) · JSONValue + ClaudeClient (Messages API, retries)
  PetStats/PetEngine/PetStore (pet needs, from 1.0)
Sources/DeskPet/
  App/        AppDelegate (composition root), AppModel (source of truth + events),
              CommandExecutor (the one place commands run), ReminderScheduler,
              NotificationManager, HotKeyManager, PetMenu, StatusBarController, SelfTest
  AI/         ChatModel (local-first routing, context follow-ups, undo, tool loop, permissions), AssistantTools, Keychain
  Voice/      SpeechRecognizerService (push-to-talk, on-device), SpeechSynthesizerService, VoiceController
  Worlds/     WorldsController (window + navigation over the shared timer), WorldTheme, WorldScenery,
              WorldPet, AmbientAudioEngine (synthesized), FrameClock, lobby + five world views, summary
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

* `scripts/build-app.sh` builds are ad-hoc signed for local use; use
  `scripts/release.sh` for a notarized build that opens cleanly on other Macs.
* Release builds are Apple Silicon (arm64) only.
* macOS notifications and Open at Login require running the
  `.app` (not `swift run`). In-pet reminders always work.
* Reminders only fire while DeskPet is running.
* Calendar heads-up reads macOS Calendar only (add Google/Outlook accounts there).
* The distraction guard can't read Firefox tabs (no Apple Events support); listed apps still work.
* AI chat responses aren't streamed; a typing indicator shows while waiting.
* Voice needs the `.app` bundle (it declares the microphone and speech
  recognition usage). On-device recognition depends on the language and Mac.
* The speech-to-text round-trip self-test runs only after you've granted Speech
  Recognition access in the app once. It's skipped otherwise, so tests never
  trigger permission prompts.

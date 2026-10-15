# DeskPet

A tiny pixel-art cat that lives on your Mac desktop. Pet it, feed it, play with
it, and let it nap — it floats above your windows without ever getting in the way.

Native Swift + SwiftUI + AppKit. No dependencies, no network, no data collection.

## Run it

Requires macOS 14+ and either Xcode or just the Command Line Tools
(`xcode-select --install`).

```sh
scripts/build-app.sh          # builds build/DeskPet.app (release, ad-hoc signed)
open build/DeskPet.app
```

To install, drag `build/DeskPet.app` into `/Applications`.

For quick iteration you can also `swift run DeskPet` (Open at Login is unavailable
in that mode because it needs a real app bundle).

Tests (core pet logic + persistence):

```sh
scripts/test.sh
```

## Using DeskPet

| Do this | What happens |
| --- | --- |
| Click the cat | Petting: purrs, hearts, happiness up |
| Drag the cat | Moves it anywhere; it snaps back on-screen if dropped off the edge |
| Hover the cat | Action bar: **Feed · Play · Nap/Wake · Settings** |
| Right-click / ⌃-click | Mood, stats and all actions |
| 🐾 in the menu bar | Show/Hide, bring back to screen, stats, actions, Settings, Quit |

**Needs** (0–100): *Happiness*, *Energy*, *Hunger*. They drift slowly while the app
runs. Feeding lowers hunger; playing raises happiness but costs energy (the cat
refuses when exhausted); napping restores energy (about 25 minutes from empty) and
the cat wakes up on its own when rested.

**Forgiving by design:** time away (app closed or Mac asleep) counts for at most
8 hours, and absence never drops happiness below 40 or energy below 30, or pushes
hunger above 70 — unless they were already worse.

## Settings

Pet name and size (S/M/L) · show/hide · animations (also honours the system
*Reduce motion* setting) · sound effects (**off by default**; uses built-in macOS
sounds) · chatty speech bubbles · Open at Login (`SMAppService`) · Start Over.

## Architecture

```
Sources/
  DeskPetCore/            Pure logic, no UI — unit tested
    PetStats.swift          Clamped 0–100 needs + mood
    PetEngine.swift         Decay rates, offline forgiveness, action rules
    PetStore.swift          JSON persistence (atomic writes, corrupt-file recovery)
  DeskPet/
    App/                  main.swift, AppDelegate (composition root),
                          StatusBarController (menu bar), PetMenu (shared menus)
    Pet/                  PetViewModel (timers, actions, speech), Speech, SoundPlayer
    Rendering/            PixelSprite/CatSprite (original pixel art → cached CGImages),
                          PetAnimator (pure frame function), PetAnimationDriver,
                          IconRenderer (app icon + preview sheet)
    Window/               PetPanel (borderless floating NSPanel), PetWindowController
                          (click-through, clamping, positioning), PetLayout,
                          PetInteractionView (click vs drag), AuxWindowController
    Settings/             AppSettings (UserDefaults), LoginItemManager (SMAppService)
    Views/                PetView (scene, bubble, action bar), SettingsView, WelcomeView
Tests/DeskPetCoreTests/   Swift Testing suite
scripts/                  build-app.sh, test.sh
```

**Click-through:** a borderless window normally swallows clicks across its whole
rectangle. DeskPet reads only the cursor *position* (~12×/s while visible) and
sets `ignoresMouseEvents` so clicks pass through everywhere except the cat and its
visible action bar. No keystrokes, clicks elsewhere, or screen contents are read.

**Efficiency:** each sprite pose is rasterised once into a tiny bitmap and scaled
with nearest-neighbour filtering. A timer evaluates the animation (6 fps idle,
10 asleep, 15 during reactions) and publishes only frames that differ, so idle CPU
is ≈0.5% and memory is ~13 MB. Everything stops while the pet is hidden.

**Data:** `~/Library/Application Support/DeskPet/pet.json` (pet) and the
`app.deskpet.DeskPet` defaults domain (preferences, window position).
Unreadable save files are moved aside as `pet-corrupt-<timestamp>.json`.

Render all animation states to a PNG (QA / press kit):

```sh
.build/release/DeskPet --export-previews ./previews
```

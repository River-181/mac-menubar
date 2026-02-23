# NotchDock

NotchDock is a fresh rewrite focused on one thing: a notch-linked, tactile overlay dock that keeps the macOS menu bar compact and visually clean.

## Project Reset

- Previous implementation is archived at:
  - `/Users/river/project/mac-menubar/archive/mac-menubar-legacy-v1`
- New app root:
  - `/Users/river/project/mac-menubar/NotchDock`

## Current Scope (v0 scaffold)

- LSUIElement menu bar app (Dock icon hidden)
- Top-center overlay capsule with state machine:
  - `idle -> peek -> expand -> workspace`
- Status bar control (left click toggle, right click menu)
- Basic icon strip model (`Pinned` + `Shelf`)
- Basic settings scene (policy + motion toggles)

## Build

```bash
cd /Users/river/project/mac-menubar
xcodegen generate
xcodebuild -resolvePackageDependencies -project NotchDock.xcodeproj -scheme NotchDock
xcodebuild -project NotchDock.xcodeproj -scheme NotchDock -configuration Debug -destination 'platform=macOS' build
xcodebuild -project NotchDock.xcodeproj -scheme NotchDock -destination 'platform=macOS' test
```

## External Packages

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts): global hotkeys for overlay/workspace/group navigation.

## Phase Plan (A -> E)

- Phase A: dependencies + hotkey infrastructure
- Phase B: top-trigger/drag stability + energy optimization
- Phase C: icon dock behavior polish (group cycle/filter)
- Phase D: work-action execution responsiveness and reliability
- Phase E: docs/tests/review loop and repeat

## Notes

- This reset intentionally starts from a clean architecture baseline.
- The full interaction spec is tracked in `/Users/river/project/mac-menubar/spec.md`.

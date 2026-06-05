# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

The project uses XcodeGen — regenerate the Xcode project whenever `project.yml` changes:

```bash
xcodegen generate
xcodebuild -resolvePackageDependencies -project NotchDock.xcodeproj -scheme NotchDock
xcodebuild -project NotchDock.xcodeproj -scheme NotchDock -configuration Debug -destination 'platform=macOS' build
```

Run all tests:
```bash
xcodebuild -project NotchDock.xcodeproj -scheme NotchDock -destination 'platform=macOS' test
```

Run a single test:
```bash
xcodebuild test -project NotchDock.xcodeproj -scheme NotchDock \
  -only-testing:NotchDockTests/OverlayStateMachineTests/testClickFlow
```

## Architecture Overview

NotchDock is an LSUIElement macOS app (no Dock icon) that renders a notch-connected overlay capsule at the top-center of the screen. All UI state flows through a single `@MainActor` ObservableObject (`NotchDockViewModel`) driven by a timer-based pointer sampling loop.

### Layer Map

**`NotchDock/Models/NotchDockModels.swift`** — all types and protocols in one file:
- `OverlayState`: `hidden → armed → peek → expand → processing`
- `OverlayEvent`: pointer/drag/click events fed into the state machine
- `WorkActionKind`: 15 file-conversion actions (imageToPDF, compressZip, etc.)
- All service protocols (`WorkActionExecuting`, `IconSourceProviding`, `NotchGeometryCalculating`, `DropRoutingProviding`, `IconPolicyProviding`, `TriggerProviding`, `DragPipelining`)

**`NotchDock/Core/`** — pure, protocol-backed engines:
- `OverlayStateMachine`: pure reducer `(state, event, isDragging) → state`
- `TriggerEngine`: debounced hysteresis (enter: 35ms, exit: 100ms) converts raw pointer-inside booleans to `OverlayEvent`
- `DragPipeline`: raw `CGPoint` samples → `DropTelemetry` with velocity
- `HitMaskEngine`: capsule hit testing (visual bounds + 8pt padding)
- `DropRoutingEngine`: classifies dropped files, resolves which `WorkActionKind` to run

**`NotchDock/ViewModel/NotchDockViewModel.swift`** — singleton `ObservableObject`:
- All state changes funnel through `transition(_:)` → `OverlayStateMachine.reduce` → `refreshPresentation()`
- `ingestPointerSample(...)` is called on every timer tick by `OverlayWindowController`
- `performDrop(inputs:target:)` executes work actions and manages undo tokens
- Tracks perf counters: `idleCPUPercent`, `triggerFlaps`, `avgDragFrameMs`
- `presentationState` differs slightly from `overlayState` — adds an `.armed` visual intermediate when cursor is near the trigger zone

**`NotchDock/Controllers/`**:
- `OverlayWindowController`: owns the borderless `NSPanel` at `.statusBar` level; runs the adaptive sampling timer (idle: 180ms, armed: 60ms, drag: 30ms); dynamically toggles `panel.ignoresMouseEvents` based on hit-mask result; samples idle CPU via `task_info` every 2s
- `StatusBarController`: menubar icon + right-click context menu (perf readout, Reset Perf Counters, Settings, Quit)

**`NotchDock/Services/`**:
- `WorkActionService`: executes file conversions; writes output to `~/Downloads/NotchDock/YYYY-MM-DD/`; issues `UndoToken` with 8s expiry for destructive operations
- `NotchGeometryCalculator`: derives trigger frame and panel frame from `NSScreen.safeAreaInsets` (used to detect notch presence and width)
- `HotkeyService`: global hotkeys via `KeyboardShortcuts` (⌥Space toggle, ⌥⌘Z undo)

**`NotchDock/Views/`** — SwiftUI views hosted in the panel via `NSHostingView`:
- `OverlayRootView` → `DropHubView` (action chip grid); `DropPayload` is the shared `[NSItemProvider] → [URL]` loader used by both drop sites
- Mouse pass-through uses `OverlayPassThroughContainerView`, a custom `NSView` subclass that overrides `hitTest(_:)` to return `nil` for points outside the capsule hit-mask
- Accessibility labels + `accessibilityReduceMotion` gating are applied throughout

> **Scope note:** the menu-bar *icon-organization* feature (`IconStripView`, `IconSourceService`,
> `IconPolicyEngine`, `DockIcon`) was removed — the product is focused on the file drag-and-drop
> Work Hub. Distribution is **Developer ID + notarization** (not MAS), so there is no App Sandbox;
> see `NotchDock.entitlements`, `PrivacyInfo.xcprivacy`, and `docs/v1-app-store-readiness-plan.md`.

### Key Invariants

- The panel is always `ignoresMouseEvents = true` by default; `OverlayWindowController.sample()` re-enables it only when the pointer is inside the capsule or top-trigger zone.
- `OverlayStateMachine` is a pure value type — no side effects, fully covered by unit tests.
- All protocol dependencies are injected into `NotchDockViewModel`'s `init`, making unit-testing straightforward with mock implementations.
- Drag detection relies on `NSPasteboard(name: .drag)` polling because macOS drag sessions don't expose a global "drag in progress" API.

### Performance KPIs

- Idle CPU ≤ 1.5%
- Trigger false-positive rate: 0–1 per 50 drags
- Drag sampling target: ~60fps (≤ 16ms avg frame)

## External Packages

Declared in `project.yml` (SPM), resolved automatically:

| Package | Purpose |
|---|---|
| KeyboardShortcuts | Global hotkeys (⌥Space toggle, ⌥⌘Z undo) |
| ZIPFoundation | ZIP/extract engine |
| SnapshotTesting | UI regression tests (test target only) |
| sentry-cocoa | Crash reporting (requires `SENTRY_DSN` in Info.plist) |
| LaunchAtLogin-Modern | Login item management |

## Tests

Unit tests live in `Tests/`. Notable test files:
- `OverlayStateMachineTests`: state transition coverage + `TriggerEngine` hysteresis
- `NotchGeometryCalculatorTests`: trigger frame / hit-mask geometry
- `HitMaskEngineTests`, `DropRoutingEngineTests`, `WorkActionServiceTests`, `ViewModelTriggerTests`

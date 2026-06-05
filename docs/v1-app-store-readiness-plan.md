# NotchDock v1 — Release-Quality Plan (Developer ID + Notarization)

## Context

NotchDock is a notch-anchored macOS overlay that detects file drags from any app and runs
instant file-conversion actions (the "Work Hub"). A 4-agent evaluation found the core
architecture sound but the primary drag-to-drop flow broken by logic bugs, the menu-bar icon
feature only half-built (hardcoded dummies), and **all** distribution artifacts (entitlements,
app icon, hardened runtime, privacy manifest, `LSUIElement`) missing.

**Confirmed product decisions:**

1. **Distribution: Developer ID + Notarization** (not Mac App Store). The core drag-pasteboard
   polling and LibreOffice subprocess are incompatible with the MAS sandbox; Developer ID keeps
   100% of functionality at the same quality bar.
2. **Product identity: "Notch file drag-and-drop Work Hub."** The fake menu-bar icon strip is
   removed entirely — it reads no real system icons and conflicts with the sandbox model.
3. **Scope: v1 daily-driver quality** — fix critical bugs, stabilize drag/drop, add
   accessibility + Reduce Motion, first-run safety, undo affordance, and produce all signing /
   notarization / icon / privacy artifacts.
4. **Build env:** full Xcode + Apple Developer account available (user runs build/sign; we guide).

## Evaluation Summary (baseline)

| Area | State |
|---|---|
| Drag-to-drop core flow | **Broken** — dead `if/else` ends drag session early (`NotchDockViewModel.swift:126-130`) |
| State animations | Bypassed by direct state mutations (`:89-95`, `:405-414`) |
| PDF render | Crash on failure — `NSGraphicsContext.current!` (`WorkActionService.swift:463`) |
| Expand state | Strands if drag ends without drop (`:154-156`) |
| 15 work actions | Real & spec-compliant (PDFKit/ImageIO/ZIPFoundation); `optimizePDFKeepText` is a near-no-op re-save |
| Undo (8s) | Engine complete; toast Undo button exists; no keyboard affordance |
| Icon feature | Hardcoded 8 dummies; **to be removed** |
| Settings window | Dual-window bug (SwiftUI `Settings` scene + AppDelegate `NSWindow`) |
| Accessibility / Reduce Motion | Absent everywhere |
| Distribution artifacts | All missing |

## Workstreams (4 parallel agents, disjoint file ownership)

### Stream 1 — ViewModel + Models (core logic)
Files: `NotchDock/ViewModel/NotchDockViewModel.swift`, `NotchDock/Models/NotchDockModels.swift`,
`Tests/ViewModelTriggerTests.swift`
- Fix dead `if/else`: only `endDragSession()` when **not** dragging → drag session survives a
  momentary pointer exit while a system drag continues.
- Wrap state mutations in `withAnimation(...)` (armed/hidden warm-up, leave-grace collapse).
- `endDragSession`: also `transition(.dragEnded)` when state is `.expand` (not only `.processing`).
- Add `isDropExecutionInProgress` guard so the sampling timer can't reset `dropHubState` mid-`performDrop`.
- **Remove icon feature:** drop `iconSource`/`iconPolicy` deps; `visibleIcons`/`overflowIcons`/
  `candidateIcons`/`selectedIconIDs`/`allSelectedIcons`; `refreshIcons`/`setIconEnabled`/
  `recomputeIconLayout`; remove icon terms from `resolvedPanelSize`. Remove `DockIcon`,
  `IconBucket`, `IconPolicyResult`, `IconSourceProviding`, `IconPolicyProviding` from Models.
- **First-run safety:** before the first destructive action (trash-on-compress/optimize/resize/
  moveToTrash), show a one-time `NSAlert` gated by a `Defaults` flag, explaining originals go to Trash.
- Update `ViewModelTriggerTests` for the new init signature; add a regression test that the drag
  session persists across a momentary exit and that `.expand` collapses on `dragEnded`.

### Stream 2 — Overlay views (presentation + a11y)
Files: `NotchDock/Views/OverlayRootView.swift`, `NotchDock/Views/DropHubView.swift`,
new `NotchDock/Views/DropPayload.swift`
- Remove `IconStripView(...)` embed (`OverlayRootView.swift:46-49`).
- Extract the duplicated `loadURLs` into `DropPayload.swift` (one `[NSItemProvider]` helper); call
  from both drop sites.
- Accessibility: `.accessibilityLabel`/`.accessibilityHint`/`.isButton` on every `DropChip` and the
  toast Undo button; label the panel as a group.
- Reduce Motion: read `@Environment(\.accessibilityReduceMotion)`; gate spring/scale/move
  transitions to plain opacity when enabled.
- Fix click-mode grid (`minimum: 280` forces a single column) → two flexible columns.

### Stream 3 — App lifecycle / hotkeys / status bar
Files: `NotchDock/App.swift`, `NotchDock/AppDelegate.swift`, `NotchDock/Services/HotkeyService.swift`,
`NotchDock/Controllers/StatusBarController.swift`
- **Settings single window:** remove the SwiftUI `Settings {}` scene; keep one AppDelegate-managed
  `NSWindow` that reuses/raises the existing instance and calls `NSApp.activate`.
- `LSUIElement`: ensure `NSApp.setActivationPolicy(.accessory)` at launch (belt-and-suspenders with
  Info.plist).
- Sentry `environment`: derive `"production"`/`"development"` from build config, not hardcoded.
- Hotkeys: keep ⌥Space toggle; add a global **⌥⌘Z undo** (`undoLastDangerousAction`). Drop the
  now-obsolete ⌥←/→ and ⌥/ icon/group/search shortcuts.
- StatusBar: remove the "Overflow Icons" menu item (icon feature gone).
- `IconStripView` reference removal verified here too.

### Stream 4 — Distribution config + app icon + crash fix
Files: `project.yml`, `NotchDock/Info.plist`, new `NotchDock/NotchDock.entitlements`,
new `NotchDock/PrivacyInfo.xcprivacy`, new `NotchDock/Assets.xcassets/AppIcon.appiconset/*`,
`NotchDock/Services/WorkActionService.swift` (only the force-unwrap fix)
- `project.yml`: `ENABLE_HARDENED_RUNTIME: YES`, `CODE_SIGN_ENTITLEMENTS`, `MARKETING_VERSION` /
  `CURRENT_PROJECT_VERSION`, `DEVELOPMENT_TEAM` placeholder, asset catalog as a source.
- `Info.plist`: `LSUIElement = true`, `SENTRY_DSN` key (empty default), version via
  `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)`, copyright string.
- `NotchDock.entitlements`: minimal (no App Sandbox; Developer ID + hardened runtime).
- `PrivacyInfo.xcprivacy`: `NSPrivacyTracking=false`; declare `UserDefaults` (CA92.1), file-timestamp
  / disk-space API reasons; Sentry crash-data collection type.
- App icon: generate a real capsule-motif 1024² icon via a CoreGraphics script and emit all
  `AppIcon.appiconset` sizes + `Contents.json`.
- `WorkActionService.swift:463`: guard `NSGraphicsContext.current?.cgContext` instead of force-unwrap.

### Deletions (orchestrator)
`NotchDock/Views/IconStripView.swift`, `NotchDock/Services/IconSourceService.swift`,
`NotchDock/Core/IconPolicyEngine.swift`, `Tests/IconDockServiceTests.swift`.

## Cross-stream contracts (must hold for compile)
- ViewModel no longer exposes `visibleIcons`, `overflowIcons`, `candidateIcons`, `selectedIconIDs`,
  `setIconEnabled`, `refreshIcons` (Streams 2 & 3 must not reference them).
- ViewModel `init` drops `iconSource`/`iconPolicy` params (App.swift uses `.shared`; tests updated).
- First-run alert lives in the ViewModel (AppKit `NSAlert`), so views need no extra wiring.
- ⌥⌘Z calls the existing `viewModel.undoLastDangerousAction()`.

## Out of scope (v1)
- Workspace canvas, real system menu-bar icon discovery/hiding, true text-preserving PDF image
  recompression (kept as honest re-save with accurate byte-delta messaging), MAS sandbox build.

## Verification
1. Switch toolchain if needed: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
2. `xcodegen generate`
3. `xcodebuild -resolvePackageDependencies -project NotchDock.xcodeproj -scheme NotchDock`
4. Build: `xcodebuild -project NotchDock.xcodeproj -scheme NotchDock -configuration Debug -destination 'platform=macOS' build`
5. Test: `xcodebuild -project NotchDock.xcodeproj -scheme NotchDock -destination 'platform=macOS' test`
6. Manual: drag files from Finder over the notch → hub expands, chips highlight, drop runs the
   action, toast shows result + Undo; ⌥⌘Z undoes; first destructive action shows the one-time notice;
   enable Reduce Motion and VoiceOver and re-check.
7. Release sign + notarize (user runs, with their cert/team):
   `xcodebuild -configuration Release -scheme NotchDock -derivedDataPath build archive`-style export,
   then `xcrun notarytool submit ... --wait` and `xcrun stapler staple`.

## Risk notes
- I cannot build here (this shell has CLT, not full Xcode); contract correctness is enforced by a
  post-integration grep sweep and the user's local build.
- Global ⌥Space / ⌥⌘Z and drag-pasteboard polling require the user to grant Accessibility permission
  on first run; add a gentle prompt if `AXIsProcessTrusted()` is false.

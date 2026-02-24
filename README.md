# NotchDock

NotchDock v1 hard reset focuses on a stable notch drag hub first.

## Current Scope (v1)

- LSUIElement menu bar app (Dock icon hidden)
- Strict notch trigger overlay:
  - `hidden -> armed -> peek -> expand -> processing`
- Pass-through panel behavior:
  - mouse interaction is captured only inside capsule/hit-mask
- Drag hub with 9 actions:
  - `imageToPDF`, `pdfToImages`, `compressZip`, `extractZip`, `optimizeImages`, `optimizePDFKeepText`, `resizeImages`, `sendToWorkbench`, `moveToTrash`
- Undo for dangerous actions (8 seconds)
- Icon policy:
  - core icons + user selection only (`Pinned/Shelf/Overflow`)
- Explicitly removed from v1:
  - Workspace canvas
  - AX external icon mirroring/hiding
  - running apps bulk auto-collection

## Build

```bash
cd /Users/river/project/mac-menubar
xcodegen generate
xcodebuild -resolvePackageDependencies -project NotchDock.xcodeproj -scheme NotchDock
xcodebuild -project NotchDock.xcodeproj -scheme NotchDock -configuration Debug -destination 'platform=macOS' build
xcodebuild -project NotchDock.xcodeproj -scheme NotchDock -destination 'platform=macOS' test
```

## External Packages

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts): toggle hotkey.
- [Defaults](https://github.com/sindresorhus/Defaults): selected icon persistence.
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation): in-app ZIP/extract engine foundation.
- [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing): snapshot-based UI regression testing.
- [sentry-cocoa](https://github.com/getsentry/sentry-cocoa): crash/performance reporting pipeline.
- [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern): login-item management.

## Optional Runtime Configuration

- `SENTRY_DSN` (`/Users/river/project/mac-menubar/NotchDock/Info.plist`): set a real DSN to enable Sentry reporting.

## Notes

- Previous code snapshots:
  - `/Users/river/project/mac-menubar/archive/mac-menubar-legacy-v1`
  - `/Users/river/project/mac-menubar/archive/notchdock-pre-rebuild-v1/NotchDock`
- Full product spec is tracked in `/Users/river/project/mac-menubar/spec.md`.

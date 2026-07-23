# Uninstaller — design

**Date:** 2026-07-23
**Status:** approved (design), pending implementation plan

A native macOS app named **Uninstaller** that removes an application *and all of
its leftover files*, plus a **Cleanup** tab that reclaims space from orphaned
leftovers, caches, and logs. Everything it removes goes to the **Trash** — fully
reversible. The mark is a clean trash-bin / dump icon.

---

## 1. Goals & non-goals

**Goals**
- Uninstall an app completely: the `.app` bundle **and** every associated support
  file scattered across `~/Library`.
- A Cleanup action that targets three categories: **orphaned leftovers**, **caches**,
  **logs & crash reports**.
- Fast: scanning and size calculation fan out concurrently; the UI stays responsive.
- Safe: Trash-only, strict allowlist of deletable locations, explicit confirmation.

**Non-goals (YAGNI)**
- No permanent/`rm` delete (Trash only).
- No Trash-emptying or Downloads management in Cleanup (explicitly deselected).
- No Mac App Store distribution (an uninstaller cannot be sandboxed).
- No auto/background cleaning, no scheduling, no analytics.
- No uninstall of system/Apple apps.

---

## 2. Form factor & tech

- **Single-window SwiftUI app**, two tabs: **Apps** and **Cleanup**.
- SwiftPM executable target that `import SwiftUI`, assembled into a
  `Uninstaller.app` bundle (`Info.plist` + generated `AppIcon.icns`) and launched
  with `open`. Confirmed buildable on **CommandLineTools + Swift 6.2** (no full
  Xcode). macOS 26.3 target.
- App icon generated from a clean trash-bin SVG → `.icns` via `iconutil`.

---

## 3. Architecture — units

Each unit has one purpose, a defined interface, and is understandable in isolation.

| Unit | Responsibility | Depends on |
|---|---|---|
| `AppScanner` | Enumerate apps in `/Applications` and `~/Applications`; read `CFBundleIdentifier`, display name, icon, on-disk size. | FileManager, SizeCalculator |
| `LeftoverFinder` | Given `(bundleID, appName)`, return every associated file/dir across the known Library locations. **Pure** — takes a `libraryRoot` URL so it is testable against a fixture. | (injected root) |
| `CleanupScanner` | Produce categorized removable items for Cleanup: orphaned leftovers, caches, logs/crash reports. Reuses the installed-bundle-id set to detect orphans. | AppScanner (bundle-id set), SizeCalculator |
| `SizeCalculator` | Concurrent allocated-size calc for files/dirs. | FileManager |
| `Remover` | Move a set of URLs to Trash via `FileManager.trashItem`; return per-item success/failure. The **only** unit that deletes. | FileManager |
| SwiftUI views + view models | `RootView` (tab shell), `AppsView`, `CleanupView`, `AppsViewModel`, `CleanupViewModel`. | the units above |

### 3.1 Known Library locations (the allowlist)

`LeftoverFinder` and `CleanupScanner` only ever look inside — and only ever delete
from — this fixed set under `~/Library` (and the `.app` itself for uninstall):

```
Application Support/            Caches/
Preferences/                    Logs/
Saved Application State/        Containers/
Group Containers/               HTTPStorages/
WebKit/                         Cookies/
Application Scripts/            LaunchAgents/
Internet Plug-Ins/              Application Support/CrashReporter/
Logs/DiagnosticReports/
```

System-wide `/Library/LaunchAgents`, `/Library/LaunchDaemons` are **scanned read-only
and shown**, but flagged as requiring admin; not deleted in v1 without an explicit
admin escalation (deferred — see §7).

---

## 4. Matching rules (the core correctness concern)

The single most dangerous bug is a **false-positive leftover match** that trashes an
unrelated app's data. Defenses:

- **Bundle-id match (checked by default):** a path matches only if its name equals the
  bundle id exactly, or begins with `bundleID + "."` (e.g. `com.spotify.client` and
  `com.spotify.client.helper`), or is `bundleID + ".plist"` /
  `bundleID + ".savedState"`. **Substring matching is never used.**
- **Name match (shown, NOT checked by default):** folders named after the app's display
  name (e.g. `Application Support/Spotify`) are surfaced as *suggestions* the user can
  opt into, because name collisions are real.
- **Apple/system guard:** any `com.apple.*` id, and a small denylist of shared
  frameworks, are never offered for deletion.
- **Never** delete a Library subdirectory root itself — only entries within it.

---

## 5. Data flow

**Apps tab**
1. `AppScanner` lists installed apps (icon, name, size) — streamed as sizes resolve.
2. User selects an app, or drags a `.app` onto the window.
3. `LeftoverFinder(bundleID, name)` → the `.app` + leftovers, each a checkbox row with
   size. Bundle-id matches pre-checked; name-only matches unchecked.
4. **Uninstall** → confirmation (N items, total size) → `Remover` → Trash → list refreshes.

**Cleanup tab**
1. On open (or Rescan), run the 3 categories concurrently via `CleanupScanner`.
2. Categorized checklist with per-item and per-category reclaimable size.
3. **Cleanup** → confirmation → `Remover` → Trash.

---

## 6. Performance

- Directory enumeration and `SizeCalculator` run on `async` tasks via `TaskGroup`.
- The installed-bundle-id set is computed **once** by `AppScanner` and reused by
  `CleanupScanner` for orphan detection (the otherwise-expensive matching path).
- Sizes stream into the UI as they finish; the list renders before all sizes resolve.
- No blocking of the main actor for filesystem work.

---

## 7. Safety, permissions, errors

- **Trash-only**, reversible. Explicit confirmation showing item count + total size
  before any `trashItem` call.
- **Allowlist** of deletable roots (§3.1); refuse anything outside it.
- **Full Disk Access:** user-owned `~/Library` files trash without special rights. A few
  protected folders (Safari/Mail/Messages) need FDA; the app **detects** unreadable
  protected locations and shows a one-line "grant Full Disk Access for a deeper scan"
  hint with a button that opens the relevant System Settings pane. Never fails silently.
- **Per-item error handling:** `Remover` returns a result per URL; partial failures are
  reported (e.g. "3 moved, 1 skipped: permission"), nothing aborts the whole batch.
- **Deferred to a later version:** admin-escalated removal of `/Library` LaunchDaemons;
  permanent-delete option; running-process detection before uninstall.

---

## 8. Testing

- `LeftoverFinder`: XCTest against a fake `libraryRoot` fixture. Assert exact-id and
  `id.`-prefix paths match, `.plist`/`.savedState` match, **substring near-misses do
  not**, `com.apple.*` is skipped, name-only matches are returned as unchecked.
- `CleanupScanner`: fixture with some orphaned bundle-id dirs (no installed app) and some
  live ones; assert only orphans are flagged, categories are correct, sizes summed.
- `SizeCalculator`: known-size temp tree → expected total.
- `Remover`: verify correct URL set collected; dry-run mode asserted (does not require
  hitting the real Trash in tests).

---

## 9. Project layout

```
uninstaller/
  Package.swift
  Sources/
    UninstallerCore/        AppScanner, LeftoverFinder, CleanupScanner,
                            SizeCalculator, Remover, models  (pure, testable)
    UninstallerApp/         SwiftUI @main App, RootView, AppsView, CleanupView,
                            view models
  Tests/
    UninstallerCoreTests/
  Resources/
    icon.svg                clean trash-bin / dump mark
  Scripts/
    make-app.sh             build → assemble Uninstaller.app → generate .icns
  docs/superpowers/specs/
```

Core logic lives in `UninstallerCore` (no SwiftUI import) so it is unit-testable and the
UI layer stays thin.

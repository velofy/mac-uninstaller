# Uninstaller

A fast, native macOS app that removes an application **and all of its leftover
files**, plus a **Cleanup** panel that reclaims space from orphaned support files,
caches, and logs. Everything it removes goes to the **Trash** — nothing is deleted
outright, so anything can be restored until you empty the Trash.

Built in SwiftUI. Runs on Apple silicon, macOS 14+.

<br>

## What it does

**Apps tab** — pick an installed app (or drag a `.app` onto the window). Uninstaller
finds the bundle plus every associated file scattered across `~/Library`
(Application Support, Caches, Preferences, Logs, Saved State, Containers, Group
Containers, and more), shows them with sizes, and moves the selected ones to the
Trash in one click.

**Cleanup tab** — scans for three kinds of reclaimable space:

- **Orphaned leftovers** — support/pref/container folders whose app is no longer installed.
- **Caches** — regenerable data in `~/Library/Caches`.
- **Logs & crash reports** — logs, diagnostic and crash reports.

## Safety

- **Trash only.** Uses `FileManager.trashItem`; never `rm`. Reversible.
- **Precise matching.** Association is by exact bundle id or a dot-bounded prefix/suffix
  (`com.foo.bar`, `com.foo.bar.helper`, `group.com.foo.bar`) — **never a bare substring**,
  so a sibling like `com.foo.barbecue` is never swept up. Folders merely *named* after an
  app are shown but left **unchecked** for you to confirm.
- **System-safe.** Apple bundle ids (`com.apple.*`) and shared identifiers are never offered.
- **Explicit confirmation** on item count and total size before anything moves.

A few protected folders (Safari/Mail/Messages data) need Full Disk Access to scan; grant it
in System Settings for a deeper sweep. It is not required for the common case.

## Build & install

Requires the Swift toolchain (Xcode or Command Line Tools). No Xcode project needed.

```bash
# build build/Uninstaller.app
Scripts/make-app.sh

# build, copy to /Applications, and launch
Scripts/make-app.sh --install
```

## Develop

```bash
swift build            # compile the app
swift run corecheck    # run the core matching/scanning assertions
swift run Uninstaller  # run from the terminal
```

## Layout

```
Sources/
  UninstallerCore/   AppScanner · LeftoverFinder · CleanupScanner ·
                     BundleMatcher · SizeCalculator · Remover  (pure, no SwiftUI)
  Uninstaller/       SwiftUI app: RootView, AppsView, CleanupView, view models
  corecheck/         standalone assertion runner for the core
Resources/           icon.svg, AppIcon.icns, Info.plist
Scripts/make-app.sh  assemble & install the .app bundle
docs/                design spec
```

The correctness-critical logic lives in `UninstallerCore` with no UI dependency, so it is
tested in isolation via `corecheck` (runs under plain Command Line Tools, no Xcode).

## License

MIT — see [LICENSE](LICENSE).

<p align="center">
  <a href="https://velofy.co/mac-uninstaller/"><picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/velofy/mac-uninstaller/main/assets/tile-dark.svg">
    <img alt="Uninstaller" src="https://raw.githubusercontent.com/velofy/mac-uninstaller/main/assets/tile-light.svg" width="360">
  </picture></a>
</p>

# Uninstaller

A fast, native macOS app that removes an application **and all of its leftover files**, plus a **Cleanup** panel that reclaims space from orphaned support files, caches and logs. Everything it removes goes to the **Trash**. Nothing is deleted outright, so anything can be restored until you empty the Trash.

Built in SwiftUI. macOS 14 or later; the project states it runs on Apple silicon.

[![License: MIT](https://img.shields.io/github/license/velofy/mac-uninstaller)](LICENSE)

**Docs: https://velofy.co/mac-uninstaller/**

## Install

There are no releases or Homebrew cask yet. Build from source. This needs the Swift toolchain (Xcode or Command Line Tools); no Xcode project is needed.

```sh
git clone https://github.com/velofy/mac-uninstaller.git
cd mac-uninstaller

# build build/Uninstaller.app
Scripts/make-app.sh

# build, copy to /Applications, and launch
Scripts/make-app.sh --install
```

More: [Installation](https://velofy.co/mac-uninstaller/installation/).

## What it does

**Apps tab.** Pick an installed app, or drag a `.app` onto the window. Uninstaller finds the bundle plus associated files in `~/Library` (Application Support, Caches, Preferences, Logs, Saved State, Containers, Group Containers and more), shows them with sizes, and moves the selected ones to the Trash in one click.

**Cleanup tab.** Scans for three kinds of reclaimable space:

- **Orphaned leftovers**: support, preference and container folders whose app is not installed.
- **Caches**: regenerable data in `~/Library/Caches`.
- **Logs and crash reports**: logs, diagnostic reports and crash reports.

## Safety

- **Trash only.** Uses `FileManager.trashItem`, never `rm`. Reversible.
- **Precise matching.** Association is by exact bundle id or a dot-bounded prefix or suffix (`com.foo.bar`, `com.foo.bar.helper`, `group.com.foo.bar`), never a bare substring, so `com.foo.barbecue` is not swept up. Folders merely named after an app are shown but left unchecked.
- **System-safe.** Apple bundle ids (`com.apple.*`) and shared identifiers are never offered.
- **Explicit confirmation** with item count and total size before anything moves.

A few protected folders (Safari, Mail, Messages data) need Full Disk Access to scan. It is not required for the common case.

Cleanup can over-report orphans (for example for apps installed outside `/Applications` and `~/Applications`), so review the list before you confirm. Read [Safety and limitations](https://velofy.co/mac-uninstaller/safety-and-limitations/).

## Documentation

- [Overview](https://velofy.co/mac-uninstaller/)
- [Installation](https://velofy.co/mac-uninstaller/installation/)
- [First run and permissions](https://velofy.co/mac-uninstaller/first-run/)
- [Using Uninstaller](https://velofy.co/mac-uninstaller/using-uninstaller/)
- [How matching works](https://velofy.co/mac-uninstaller/how-matching-works/)
- [Safety and limitations](https://velofy.co/mac-uninstaller/safety-and-limitations/)
- [Troubleshooting](https://velofy.co/mac-uninstaller/troubleshooting/)
- [Development](https://velofy.co/mac-uninstaller/development/)

## Develop

```sh
swift build            # compile the app
swift run corecheck    # run the core matching and scanning assertions
swift run Uninstaller  # run from the terminal
```

```text
Sources/
  UninstallerCore/   AppScanner, LeftoverFinder, CleanupScanner,
                     BundleMatcher, SizeCalculator, Remover (no SwiftUI)
  Uninstaller/       SwiftUI app: RootView, AppsView, CleanupView, view models
  corecheck/         standalone assertion runner for the core
Resources/           icon.svg, AppIcon.icns, Info.plist
Scripts/make-app.sh  assemble and install the .app bundle
docs/superpowers/    design spec
```

The correctness-critical logic lives in `UninstallerCore` with no UI dependency and is checked in isolation by `corecheck`, which runs under plain Command Line Tools.

## Contributing

Issues and pull requests are welcome. Run `swift build` and `swift run corecheck` before opening a pull request.

## License

MIT. See [LICENSE](LICENSE).

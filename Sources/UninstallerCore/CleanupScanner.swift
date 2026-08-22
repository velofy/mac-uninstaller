import Foundation

/// Builds the three Cleanup categories: orphaned leftovers, caches, and
/// logs & crash reports. Pure with respect to the injected `libraryRoot` and the
/// set of installed bundle ids (so orphan detection is testable against a fixture).
public struct CleanupScanner: Sendable {
    public init() {}

    private var fileManager: FileManager { .default }

    public func scan(installedBundleIDs: Set<String>, libraryRoot: URL) -> [CleanupGroup] {
        [
            CleanupGroup(
                title: "Orphaned leftovers",
                subtitle: "Support files whose app is no longer installed",
                items: orphans(installed: installedBundleIDs, libraryRoot: libraryRoot)
            ),
            CleanupGroup(
                title: "Caches",
                subtitle: "Regenerable cache data in ~/Library/Caches",
                items: caches(libraryRoot: libraryRoot)
            ),
            CleanupGroup(
                title: "Logs & crash reports",
                subtitle: "Log files, diagnostic and crash reports",
                items: logs(libraryRoot: libraryRoot)
            ),
        ]
    }

    // MARK: - Orphans

    private func orphans(installed: Set<String>, libraryRoot: URL) -> [RemovableItem] {
        var items: [RemovableItem] = []
        for area in LibraryLocations.orphanScanAreas {
            let dir = libraryRoot.appendingPathComponent(area, isDirectory: true)
            for child in contents(of: dir) {
                let entry = child.lastPathComponent
                guard let id = BundleMatcher.canonicalBundleID(from: entry) else { continue }
                if LibraryLocations.isProtected(id) { continue }
                if installed.contains(id) { continue }
                items.append(RemovableItem(
                    url: child,
                    label: "\(area)/\(entry)",
                    category: area,
                    confidence: .bundleID,      // clearly junk -> pre-selected
                    risk: .easy,
                    riskReason: "Leftover from an app that is no longer installed; nothing uses it anymore."
                ))
            }
        }
        return items
    }

    // MARK: - Caches

    private func caches(libraryRoot: URL) -> [RemovableItem] {
        var items: [RemovableItem] = []
        for area in LibraryLocations.cacheAreas {
            let dir = libraryRoot.appendingPathComponent(area, isDirectory: true)
            for child in contents(of: dir) {
                let entry = child.lastPathComponent
                if LibraryLocations.isProtected(entry) { continue }
                items.append(RemovableItem(
                    url: child,
                    label: "\(area)/\(entry)",
                    category: area,
                    confidence: .name,          // broad -> unchecked by default
                    risk: .easy,
                    riskReason: "Regenerable: apps rebuild their caches on next launch."
                ))
            }
        }
        return items
    }

    // MARK: - Logs

    private func logs(libraryRoot: URL) -> [RemovableItem] {
        var items: [RemovableItem] = []
        for area in LibraryLocations.logAreas {
            let dir = libraryRoot.appendingPathComponent(area, isDirectory: true)
            for child in contents(of: dir) {
                let entry = child.lastPathComponent
                if LibraryLocations.isProtected(entry) { continue }
                items.append(RemovableItem(
                    url: child,
                    label: "\(area)/\(entry)",
                    category: area,
                    confidence: .name,
                    risk: .easy,
                    riskReason: "Diagnostic logs and crash reports; only useful when debugging a problem."
                ))
            }
        }
        return items
    }

    // MARK: - Helpers

    private func contents(of dir: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
    }
}

import Foundation

/// Finds every file associated with an app across the known `~/Library` areas.
///
/// Pure with respect to configuration: it reads only inside the injected
/// `libraryRoot`, so tests can point it at a fixture directory.
public struct LeftoverFinder: Sendable {
    public init() {}

    private var fileManager: FileManager { .default }

    /// - Parameters:
    ///   - appURL: the `.app` bundle (included as the first, always-selected item).
    ///   - bundleID: reverse-DNS identifier; drives the precise matches.
    ///   - appName: display name; drives the fuzzy, unchecked name suggestions.
    ///   - libraryRoot: the `~/Library` to scan.
    public func find(
        appURL: URL?,
        bundleID: String?,
        appName: String,
        libraryRoot: URL
    ) -> [RemovableItem] {
        var items: [RemovableItem] = []

        if let appURL {
            items.append(RemovableItem(
                url: appURL,
                label: appURL.lastPathComponent,
                category: "Application",
                confidence: .bundleID
            ))
        }

        // Reverse-DNS name we compare fuzzy folders against ("Spotify").
        let nameNeedle = appName.replacingOccurrences(of: ".app", with: "")

        for area in LibraryLocations.appAreas {
            let dir = libraryRoot.appendingPathComponent(area.subpath, isDirectory: true)
            guard let children = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children {
                let entry = child.lastPathComponent

                // Precise, high-confidence bundle-id match.
                if let bundleID,
                   !LibraryLocations.isProtected(bundleID),
                   BundleMatcher.matches(entryName: entry, bundleID: bundleID) {
                    items.append(RemovableItem(
                        url: child,
                        label: "\(area.category)/\(entry)",
                        category: area.category,
                        confidence: .bundleID
                    ))
                    continue
                }

                // Fuzzy, opt-in name match — only for real content areas, and only
                // when the folder name equals the app's display name exactly.
                if isNameMatchArea(area.category),
                   !nameNeedle.isEmpty,
                   entry.caseInsensitiveCompare(nameNeedle) == .orderedSame {
                    items.append(RemovableItem(
                        url: child,
                        label: "\(area.category)/\(entry)",
                        category: area.category,
                        confidence: .name
                    ))
                }
            }
        }

        // De-duplicate by URL, preferring the higher-confidence entry.
        return dedupe(items)
    }

    private func isNameMatchArea(_ category: String) -> Bool {
        ["Application Support", "Caches", "Logs"].contains(category)
    }

    private func dedupe(_ items: [RemovableItem]) -> [RemovableItem] {
        var seen: [URL: Int] = [:]
        var out: [RemovableItem] = []
        for item in items {
            if let idx = seen[item.url] {
                if item.confidence == .bundleID && out[idx].confidence == .name {
                    out[idx] = item
                }
            } else {
                seen[item.url] = out.count
                out.append(item)
            }
        }
        return out
    }
}

import Foundation

/// Enumerates installed applications and reads their identity.
public struct AppScanner: Sendable {
    public init() {}

    private var fileManager: FileManager { .default }

    /// Directories searched for `.app` bundles (user-removable apps only —
    /// `/System/Applications` is intentionally excluded).
    public func searchRoots() -> [URL] {
        var roots = [URL(fileURLWithPath: "/Applications", isDirectory: true)]
        let home = fileManager.homeDirectoryForCurrentUser
        roots.append(home.appendingPathComponent("Applications", isDirectory: true))
        roots.append(URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true))
        return roots
    }

    /// All third-party apps found, sorted by name. Sizes are left `nil` (compute
    /// lazily via `SizeCalculator` so the list appears instantly).
    public func scan() -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seen = Set<URL>()

        for root in searchRoots() {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in children where url.pathExtension == "app" {
                let std = url.standardizedFileURL
                guard !seen.contains(std) else { continue }
                seen.insert(std)

                let bundleID = Self.bundleID(of: std)
                if let bundleID, LibraryLocations.isProtected(bundleID) { continue }

                let name = std.deletingPathExtension().lastPathComponent
                apps.append(InstalledApp(bundleURL: std, name: name, bundleID: bundleID))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The set of bundle ids currently installed — used to detect orphans.
    public func installedBundleIDs() -> Set<String> {
        Set(scan().compactMap(\.bundleID))
    }

    /// Read `CFBundleIdentifier` from an app's Info.plist.
    public static func bundleID(of appURL: URL) -> String? {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any] else { return nil }
        return dict["CFBundleIdentifier"] as? String
    }
}

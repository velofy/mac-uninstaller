import Foundation

/// The fixed allowlist of `~/Library` sub-areas the app is ever allowed to read
/// from and delete within. Nothing outside this set is touched.
public enum LibraryLocations {
    /// Areas an app's leftovers can live in, as (subpath, display category) pairs.
    /// The subpath is relative to a `~/Library` root.
    public static let appAreas: [(subpath: String, category: String)] = [
        ("Application Support", "Application Support"),
        ("Caches", "Caches"),
        ("Preferences", "Preferences"),
        ("Logs", "Logs"),
        ("Saved Application State", "Saved State"),
        ("Containers", "Containers"),
        ("Group Containers", "Group Containers"),
        ("HTTPStorages", "HTTPStorages"),
        ("WebKit", "WebKit"),
        ("Cookies", "Cookies"),
        ("Application Scripts", "Application Scripts"),
        ("LaunchAgents", "LaunchAgents"),
        ("Internet Plug-Ins", "Internet Plug-Ins"),
    ]

    /// Areas scanned for orphaned bundle-id folders in the Cleanup tab.
    /// (Caches has its own category, so it is deliberately excluded here to avoid
    /// listing the same entry twice.)
    public static let orphanScanAreas: [String] = [
        "Application Support",
        "Preferences",
        "Containers",
        "Saved Application State",
        "HTTPStorages",
        "WebKit",
        "Application Scripts",
    ]

    /// Areas scanned for the Caches cleanup category.
    public static let cacheAreas: [String] = ["Caches"]

    /// Areas scanned for the Logs & crash-reports cleanup category.
    public static let logAreas: [String] = [
        "Logs",
        "Logs/DiagnosticReports",
        "Application Support/CrashReporter",
    ]

    /// Bundle-id prefixes that are never offered for deletion.
    public static let protectedPrefixes: [String] = [
        "com.apple.",
    ]

    /// Exact bundle ids / folder names shared across many apps; never offered.
    public static let protectedExact: Set<String> = [
        "com.apple",
        "CloudKit",
        "GeoServices",
        "Google",              // shared by many Google apps; too broad to auto-delete
    ]

    public static func isProtected(_ identifier: String) -> Bool {
        if protectedExact.contains(identifier) { return true }
        for p in protectedPrefixes where identifier.hasPrefix(p) { return true }
        return false
    }
}

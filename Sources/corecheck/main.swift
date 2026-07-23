import Foundation
import UninstallerCore

// Minimal assertion harness — no external test framework needed.
var failures = 0
var checks = 0
func check(_ cond: Bool, _ msg: String) {
    checks += 1
    if !cond { failures += 1; print("  ✗ \(msg)") }
}

// A throwaway ~/Library-shaped fixture.
struct Fixture {
    let root: URL
    init() {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("uninstaller-check-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func make(_ rel: String, dir: Bool = true) {
        let url = root.appendingPathComponent(rel)
        if dir {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
        }
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

// MARK: BundleMatcher

print("BundleMatcher")
check(BundleMatcher.matches(entryName: "com.spotify.client", bundleID: "com.spotify.client"), "exact")
check(BundleMatcher.matches(entryName: "com.spotify.client.helper", bundleID: "com.spotify.client"), "id.helper")
check(BundleMatcher.matches(entryName: "com.spotify.client.plist", bundleID: "com.spotify.client"), ".plist")
check(BundleMatcher.matches(entryName: "com.spotify.client.savedState", bundleID: "com.spotify.client"), ".savedState")
check(BundleMatcher.matches(entryName: "group.com.spotify.client", bundleID: "com.spotify.client"), "group. suffix")
check(BundleMatcher.matches(entryName: "9ABC.com.spotify.client", bundleID: "com.spotify.client"), "team suffix")
check(!BundleMatcher.matches(entryName: "com.spotify.clientbee", bundleID: "com.spotify.client"), "no substring: clientbee")
check(!BundleMatcher.matches(entryName: "com.spotify.clientele", bundleID: "com.spotify.client"), "no substring: clientele")
check(!BundleMatcher.matches(entryName: "org.spotify.client", bundleID: "com.spotify.client"), "different tld")
check(BundleMatcher.looksLikeBundleID("com.foo.bar"), "looksLike com.foo.bar")
check(!BundleMatcher.looksLikeBundleID("Spotify"), "looksLike Spotify == false")
check(!BundleMatcher.looksLikeBundleID("com.foo"), "looksLike com.foo == false")

// MARK: LeftoverFinder

print("LeftoverFinder")
do {
    let fx = Fixture(); defer { fx.cleanup() }
    fx.make("Application Support/com.spotify.client")
    fx.make("Caches/com.spotify.client")
    fx.make("Preferences/com.spotify.client.plist", dir: false)
    fx.make("Saved Application State/com.spotify.client.savedState")
    fx.make("Containers/com.spotify.client")
    fx.make("Application Support/com.spotify.clientbee")   // sibling
    fx.make("Caches/org.videolan.vlc")                     // unrelated

    let items = LeftoverFinder().find(
        appURL: nil, bundleID: "com.spotify.client", appName: "Spotify", libraryRoot: fx.root)
    let labels = Set(items.map(\.label))
    check(labels.contains("Application Support/com.spotify.client"), "finds app support")
    check(labels.contains("Preferences/com.spotify.client.plist"), "finds plist")
    check(labels.contains("Saved State/com.spotify.client.savedState"), "finds saved state")
    check(labels.contains("Containers/com.spotify.client"), "finds container")
    check(!labels.contains("Application Support/com.spotify.clientbee"), "skips sibling")
    check(!labels.contains(where: { $0.contains("vlc") }), "skips unrelated")
    check(items.filter { $0.confidence == .bundleID }.allSatisfy(\.isSelected), "bundle matches pre-selected")
}
do {
    let fx = Fixture(); defer { fx.cleanup() }
    fx.make("Application Support/Spotify")
    let items = LeftoverFinder().find(
        appURL: nil, bundleID: "com.spotify.client", appName: "Spotify", libraryRoot: fx.root)
    let nameItem = items.first { $0.label == "Application Support/Spotify" }
    check(nameItem != nil, "name match surfaced")
    check(nameItem?.confidence == .name, "name match confidence")
    check(nameItem?.isSelected == false, "name match unchecked")
}
do {
    let fx = Fixture(); defer { fx.cleanup() }
    fx.make("Caches/com.apple.Safari")
    let items = LeftoverFinder().find(
        appURL: nil, bundleID: "com.apple.Safari", appName: "Safari", libraryRoot: fx.root)
    check(items.isEmpty, "apple bundle never matched")
}

// MARK: CleanupScanner

print("CleanupScanner")
do {
    let fx = Fixture(); defer { fx.cleanup() }
    fx.make("Application Support/com.dead.app")      // orphan
    fx.make("Application Support/com.live.app")       // installed
    fx.make("Application Support/com.apple.thing")    // apple
    fx.make("Application Support/NotABundleFolder")   // not reverse-DNS

    let groups = CleanupScanner().scan(installedBundleIDs: ["com.live.app"], libraryRoot: fx.root)
    let orphans = groups.first { $0.title == "Orphaned leftovers" }!
    let labels = Set(orphans.items.map(\.label))
    check(labels == ["Application Support/com.dead.app"], "flags only the orphan")
    check(orphans.items.allSatisfy(\.isSelected), "orphans pre-checked")
}
do {
    let fx = Fixture(); defer { fx.cleanup() }
    fx.make("Caches/com.some.tool")
    fx.make("Logs/SomeApp")
    fx.make("Logs/DiagnosticReports/crash-1")
    let groups = CleanupScanner().scan(installedBundleIDs: [], libraryRoot: fx.root)
    let caches = groups.first { $0.title == "Caches" }!
    let logs = groups.first { $0.title == "Logs & crash reports" }!
    check(!caches.items.isEmpty, "caches found")
    check(!logs.items.isEmpty, "logs found")
    check(caches.items.allSatisfy { !$0.isSelected }, "caches unchecked by default")
    check(logs.items.allSatisfy { !$0.isSelected }, "logs unchecked by default")
}

print("\n\(checks - failures)/\(checks) checks passed")
if failures > 0 { print("FAILED: \(failures)"); exit(1) }
print("OK")

import Foundation

/// Precise, substring-free matching between a filesystem entry name and a bundle id.
///
/// This is the correctness-critical core: a loose match here trashes an unrelated
/// app's data. Every rule is anchored on dot boundaries or exact equality.
public enum BundleMatcher {

    /// True if `entryName` belongs to `bundleID` with high confidence.
    ///
    /// Accepts, for `com.foo.bar`:
    ///   - `com.foo.bar`                    (exact)
    ///   - `com.foo.bar.helper`             (id + "." + suffix)
    ///   - `com.foo.bar.plist`              (Preferences)
    ///   - `com.foo.bar.savedState`         (Saved Application State)
    ///   - `com.foo.bar.binarycookies`      (Cookies / HTTPStorages)
    ///   - `group.com.foo.bar`, `TEAMID.com.foo.bar`  (dot-bounded suffix, Group Containers)
    ///
    /// Never matches on a bare substring (e.g. `com.foo.barbecue` does NOT match).
    public static func matches(entryName rawName: String, bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return false }
        let name = strippingKnownExtension(rawName)

        if name == bundleID { return true }
        if name.hasPrefix(bundleID + ".") { return true }          // id.helper
        if name.hasSuffix("." + bundleID) { return true }          // group.id / team.id
        if name.contains("." + bundleID + ".") { return true }     // embedded, dot-bounded
        return false
    }

    /// Strip suffixes that decorate a bundle id in filenames so the core id can be
    /// compared. `com.foo.bar.plist` -> `com.foo.bar`.
    private static func strippingKnownExtension(_ name: String) -> String {
        for ext in [".plist", ".savedState", ".binarycookies"] where name.hasSuffix(ext) {
            return String(name.dropLast(ext.count))
        }
        return name
    }

    /// True if `name` looks like a reverse-DNS bundle id (at least three dot-separated
    /// labels, e.g. `com.foo.bar`). Used to spot orphaned junk folders.
    public static func looksLikeBundleID(_ name: String) -> Bool {
        // Drop a trailing known decoration first.
        let core = strippingKnownExtension(name)
        let labels = core.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 3 else { return false }
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-")
        for label in labels {
            if label.isEmpty { return false }
            if label.unicodeScalars.contains(where: { !allowed.contains($0) }) { return false }
        }
        return true
    }

    /// Extract the base bundle id from a decorated name, if it looks like one.
    /// `com.foo.bar.plist` -> `com.foo.bar`; `group.com.foo.bar` -> `group.com.foo.bar`.
    public static func canonicalBundleID(from name: String) -> String? {
        let core = strippingKnownExtension(name)
        return looksLikeBundleID(core) ? core : nil
    }
}

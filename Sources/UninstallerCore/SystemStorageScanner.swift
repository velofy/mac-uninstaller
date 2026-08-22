import Foundation

/// Finds system-level space consumers that are still safe to surface: local
/// iOS device backups and the Mail Downloads folder.
///
/// Safety rationale: only the CONTENTS of these folders are ever offered, never
/// a container folder itself, and everything still goes through the Trash-only
/// `Remover`. Backups are classified tough because a local backup can be the
/// only copy of a device's data. Deterministic with respect to the injected
/// `homeRoot`, mirroring `CleanupScanner`.
public struct SystemStorageScanner: Sendable {
    public init() {}

    private var fileManager: FileManager { .default }

    public func scan(homeRoot: URL) -> [CleanupGroup] {
        [
            CleanupGroup(
                title: "iOS device backups",
                subtitle: "Local iPhone and iPad backups made by Finder",
                items: backups(homeRoot: homeRoot)
            ),
            CleanupGroup(
                title: "Mail downloads",
                subtitle: "Copies of attachments opened from Mail",
                items: mailDownloads(homeRoot: homeRoot)
            ),
        ]
    }

    // MARK: - iOS backups

    private func backups(homeRoot: URL) -> [RemovableItem] {
        let backupRoot = homeRoot.appendingPathComponent(
            "Library/Application Support/MobileSync/Backup", isDirectory: true)
        var items: [RemovableItem] = []
        for child in contents(of: backupRoot) {
            guard isDirectory(child) else { continue }
            let udid = child.lastPathComponent
            let label: String
            if let deviceName = Self.deviceName(inBackup: child) {
                label = "\(deviceName) (\(udid))"
            } else {
                label = udid
            }
            items.append(RemovableItem(
                url: child,
                label: label,
                category: "iOS backups",
                confidence: .name,
                risk: .tough,
                riskReason: "May be the only backup of an iPhone or iPad; it cannot be recreated after the Trash is emptied.",
                modifiedAt: modificationDate(of: child)
            ))
        }
        return items
    }

    /// A backup folder's Info.plist records the device's name; showing it makes
    /// "which phone is this?" answerable before deleting anything.
    static func deviceName(inBackup dir: URL) -> String? {
        let plist = dir.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any] else { return nil }
        return (dict["Device Name"] as? String) ?? (dict["Display Name"] as? String)
    }

    // MARK: - Mail downloads

    private func mailDownloads(homeRoot: URL) -> [RemovableItem] {
        // Both the classic location and the sandboxed container location are
        // checked; only the files INSIDE are offered, never the folder itself.
        let dirs = [
            homeRoot.appendingPathComponent("Library/Mail Downloads", isDirectory: true),
            homeRoot.appendingPathComponent(
                "Library/Containers/com.apple.mail/Data/Library/Mail Downloads", isDirectory: true),
        ]
        var items: [RemovableItem] = []
        var seen = Set<URL>()
        for dir in dirs {
            for child in contents(of: dir) {
                let url = child.standardizedFileURL
                guard !seen.contains(url) else { continue }
                seen.insert(url)
                let entry = url.lastPathComponent
                if LibraryLocations.isProtected(entry) { continue }
                items.append(RemovableItem(
                    url: url,
                    label: "Mail Downloads/\(entry)",
                    category: "Mail downloads",
                    confidence: .name,
                    risk: .review,
                    riskReason: "A copy of an attachment opened from Mail; the original message usually still contains it.",
                    modifiedAt: modificationDate(of: url)
                ))
            }
        }
        return items
    }

    // MARK: - Helpers

    private func contents(of dir: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

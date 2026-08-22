import Foundation

/// One large file found under the home folder.
public struct BigFile: Identifiable, Sendable, Equatable {
    public var id: URL { url }
    public let url: URL
    public let sizeBytes: Int64
    public let modifiedAt: Date?

    public init(url: URL, sizeBytes: Int64, modifiedAt: Date?) {
        self.url = url
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
    }
}

/// Result of a big-file walk. `truncated` is surfaced so a budget-capped scan
/// never silently reads as "that was everything".
public struct BigFileScan: Sendable, Equatable {
    public var files: [BigFile]
    public var truncated: Bool

    public init(files: [BigFile], truncated: Bool) {
        self.files = files
        self.truncated = truncated
    }
}

/// Walks the injected home root for the largest user files.
///
/// Safety rationale: only the user's own home tree is entered. `~/Library` and
/// `~/Applications` are skipped (app-managed data where removing one file can
/// corrupt a store), hidden trees are skipped, package contents (a .photoslibrary,
/// a .app) are never offered file-by-file, and symlinks are not followed, so the
/// walk can never leave the home folder or touch another user's data.
public struct BigFileFinder: Sendable {
    public init() {}

    private var fileManager: FileManager { .default }

    /// Top-level home folders that are never entered.
    static let skippedTopLevelNames: Set<String> = ["Library", "Applications"]

    public func find(
        homeRoot: URL,
        minSizeBytes: Int64 = 100 * 1024 * 1024,
        limit: Int = 50,
        timeBudget: TimeInterval = 20,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> BigFileScan {
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey,
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
            .contentModificationDateKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: homeRoot,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }      // unreadable subtrees are skipped, not fatal
        ) else { return BigFileScan(files: [], truncated: false) }

        var found: [BigFile] = []
        var truncated = false
        let deadline = Date().addingTimeInterval(timeBudget)

        for case let url as URL in enumerator {
            if Date() >= deadline || isCancelled() {
                truncated = true
                break
            }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true {
                if enumerator.level == 1,
                   Self.skippedTopLevelNames.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true else { continue }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            guard size >= minSizeBytes else { continue }
            found.append(BigFile(url: url, sizeBytes: size,
                                 modifiedAt: values.contentModificationDate))
        }
        return BigFileScan(files: Self.rank(found, limit: limit), truncated: truncated)
    }

    /// Pure ranking: largest first, path as a stable tiebreaker, capped at
    /// `limit`. Split out so corecheck can pin the ordering down.
    public static func rank(_ files: [BigFile], limit: Int) -> [BigFile] {
        let sorted = files.sorted { a, b in
            if a.sizeBytes != b.sizeBytes { return a.sizeBytes > b.sizeBytes }
            return a.url.path < b.url.path
        }
        return Array(sorted.prefix(max(0, limit)))
    }
}

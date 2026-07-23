import Foundation

/// The only unit that deletes. Moves items to the Trash (reversible); never `rm`.
public struct Remover: Sendable {
    /// When true, no filesystem change is made — used by previews.
    let dryRun: Bool

    public init(dryRun: Bool = false) {
        self.dryRun = dryRun
    }

    private var fileManager: FileManager { .default }

    /// Move each URL to the Trash. Returns a per-URL result; a single failure never
    /// aborts the batch.
    public func trash(_ urls: [URL]) -> [RemovalResult] {
        urls.map { url in
            if dryRun {
                return RemovalResult(url: url, succeeded: true, error: nil)
            }
            do {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
                return RemovalResult(url: url, succeeded: true, error: nil)
            } catch {
                return RemovalResult(url: url, succeeded: false,
                                     error: (error as NSError).localizedDescription)
            }
        }
    }
}

import Foundation

/// Computes on-disk allocated sizes. Directory walks are done off the main actor.
public struct SizeCalculator: Sendable {
    public init() {}

    /// Total allocated size of a file or directory tree, in bytes.
    public func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            return Self.allocatedSize(of: url)
        }

        var total: Int64 = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let en = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        for case let child as URL in en {
            total += Self.allocatedSize(of: child)
        }
        return total
    }

    private static func allocatedSize(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        ])
        if let s = values?.totalFileAllocatedSize { return Int64(s) }
        if let s = values?.fileAllocatedSize { return Int64(s) }
        return 0
    }

    /// Compute sizes for many URLs concurrently.
    public func sizes(of urls: [URL]) async -> [URL: Int64] {
        await withTaskGroup(of: (URL, Int64).self) { group in
            let calc = self
            for url in urls {
                group.addTask { (url, calc.size(of: url)) }
            }
            var out: [URL: Int64] = [:]
            for await (url, bytes) in group { out[url] = bytes }
            return out
        }
    }
}

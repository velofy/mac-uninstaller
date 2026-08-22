import Foundation
import SwiftUI
import UninstallerCore

@MainActor
final class StorageViewModel: ObservableObject {
    @Published var groups: [CleanupGroup] = []
    @Published var snapshots: [TimeMachineSnapshot] = []
    @Published var notes: [String] = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var statusMessage: String?
    @Published var snapshotMessage: String?
    @Published var isDeletingSnapshot = false

    private let sizer = SizeCalculator()

    /// Thread-safe cancellation flag handed to the core scanners, which are
    /// plain closures rather than task-tree magic so `Task.detached` hops
    /// cannot lose the cancellation.
    private final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
        func cancel() { lock.lock(); flag = true; lock.unlock() }
    }
    private var cancelFlag = CancelFlag()

    private static let bigFilesTitle = "Big files"

    var allItems: [RemovableItem] { groups.flatMap(\.items) }
    var selectedItems: [RemovableItem] { allItems.filter(\.isSelected) }
    var selectedCount: Int { selectedItems.count }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + ($1.sizeBytes ?? 0) } }
    var summary: RiskSummary { RiskSummary(items: allItems) }

    func cancelScan() { cancelFlag.cancel() }

    func scan() async {
        cancelFlag.cancel()                     // stop any previous pass
        let flag = CancelFlag()
        cancelFlag = flag

        isScanning = true
        defer { isScanning = false; hasScanned = true }
        statusMessage = nil
        notes = []

        let home = FileManager.default.homeDirectoryForCurrentUser

        // Fixed-path scans first so rows appear immediately.
        let devScan = await Task.detached {
            let brew = DevJunkScanner.detectBrewCachePath()
            return DevJunkScanner().scan(
                homeRoot: home, brewCachePath: brew,
                isCancelled: { flag.isCancelled })
        }.value
        let systemGroups = await Task.detached {
            SystemStorageScanner().scan(homeRoot: home)
        }.value
        guard !flag.isCancelled else { return }

        var fixed = devScan.groups + systemGroups
        notes = devScan.notes
        groups = fixed + [emptyBigFilesGroup(scanning: true)]

        // Snapshots via tmutil (fast, read-only).
        snapshots = await Task.detached { SnapshotManager().list() }.value

        // Sizes for the fixed-path items.
        let urls = fixed.flatMap { $0.items.map(\.url) }
        let sizer = self.sizer
        let sizes = await Task.detached { await sizer.sizes(of: urls) }.value
        guard !flag.isCancelled else { return }
        for g in fixed.indices {
            for i in fixed[g].items.indices {
                fixed[g].items[i].sizeBytes = sizes[fixed[g].items[i].url]
            }
            fixed[g].items.sort { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
        }
        groups = fixed + [emptyBigFilesGroup(scanning: true)]

        // Big files last: the slowest walk, already size-annotated.
        let bigScan = await Task.detached {
            BigFileFinder().find(homeRoot: home, isCancelled: { flag.isCancelled })
        }.value
        guard !flag.isCancelled else { return }
        let bigItems = bigScan.files.map { file in
            RemovableItem(
                url: file.url,
                label: Self.homeRelativeLabel(file.url, home: home),
                category: Self.bigFilesTitle,
                confidence: .name,
                sizeBytes: file.sizeBytes,
                risk: .tough,
                riskReason: "May hold photos or documents not backed up elsewhere.",
                modifiedAt: file.modifiedAt
            )
        }
        if bigScan.truncated {
            notes.append("The big-file walk stopped at its time budget; the largest files seen so far are listed. Rescan to look further.")
        }
        groups = fixed + [CleanupGroup(
            title: Self.bigFilesTitle,
            subtitle: "Largest files over 100 MB in your home folder",
            items: bigItems
        )]
    }

    private func emptyBigFilesGroup(scanning: Bool) -> CleanupGroup {
        CleanupGroup(
            title: Self.bigFilesTitle,
            subtitle: scanning ? "Scanning your home folder…"
                              : "Largest files over 100 MB in your home folder",
            items: []
        )
    }

    private static func homeRelativeLabel(_ url: URL, home: URL) -> String {
        let homePath = home.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(homePath + "/") {
            return "~" + String(path.dropFirst(homePath.count))
        }
        return path
    }

    // MARK: - Selection

    func toggle(_ item: RemovableItem) {
        for g in groups.indices {
            if let i = groups[g].items.firstIndex(where: { $0.id == item.id }) {
                groups[g].items[i].isSelected.toggle()
                return
            }
        }
    }

    /// Group-level select-all deliberately skips tough items: those need
    /// explicit per-item opt-in, and that rule lives here in code.
    func setGroup(_ groupID: String, on: Bool) {
        guard let g = groups.firstIndex(where: { $0.id == groupID }) else { return }
        for i in groups[g].items.indices {
            if on && groups[g].items[i].risk == .tough { continue }
            groups[g].items[i].isSelected = on
        }
    }

    // MARK: - Removal (Trash-only, via Remover)

    func clean() async {
        let items = selectedItems
        guard !items.isEmpty else { return }
        let urls = items.map(\.url)
        let results = await Task.detached { Remover().trash(urls) }.value
        let ok = results.filter(\.succeeded).count
        let failed = results.count - ok
        statusMessage = failed == 0
            ? "Moved \(ok) item\(ok == 1 ? "" : "s") to the Trash."
            : "Moved \(ok) to the Trash, \(failed) could not be removed (permission)."
        await scan()
    }

    // MARK: - Snapshots (NOT a Trash operation; irreversible)

    func deleteSnapshot(_ snapshot: TimeMachineSnapshot) async {
        isDeletingSnapshot = true
        defer { isDeletingSnapshot = false }
        let token = snapshot.dateToken
        let result = await Task.detached {
            SnapshotManager().deleteSnapshot(dateToken: token)
        }.value
        snapshotMessage = result.message
        snapshots = await Task.detached { SnapshotManager().list() }.value
    }
}

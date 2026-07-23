import Foundation
import SwiftUI
import UninstallerCore

@MainActor
final class CleanupViewModel: ObservableObject {
    @Published var groups: [CleanupGroup] = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var statusMessage: String?

    private let libraryRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library", isDirectory: true)
    private let sizer = SizeCalculator()

    var selectedItems: [RemovableItem] { groups.flatMap { $0.items.filter(\.isSelected) } }
    var selectedCount: Int { selectedItems.count }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + ($1.sizeBytes ?? 0) } }
    var reclaimableBytes: Int64 { groups.reduce(0) { $0 + $1.totalBytes } }

    func scan() async {
        isScanning = true
        defer { isScanning = false; hasScanned = true }
        statusMessage = nil

        let root = libraryRoot
        let installed = await Task.detached { AppScanner().installedBundleIDs() }.value
        var scanned = await Task.detached {
            CleanupScanner().scan(installedBundleIDs: installed, libraryRoot: root)
        }.value
        groups = scanned                        // render immediately

        // Stream sizes in.
        let allURLs = scanned.flatMap { $0.items.map(\.url) }
        let sizer = self.sizer
        let sizes = await Task.detached { await sizer.sizes(of: allURLs) }.value
        for g in scanned.indices {
            for i in scanned[g].items.indices {
                scanned[g].items[i].sizeBytes = sizes[scanned[g].items[i].url]
            }
            // Largest first within each group.
            scanned[g].items.sort { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
        }
        groups = scanned
    }

    func toggle(_ item: RemovableItem) {
        for g in groups.indices {
            if let i = groups[g].items.firstIndex(where: { $0.id == item.id }) {
                groups[g].items[i].isSelected.toggle()
                return
            }
        }
    }

    func setGroup(_ groupID: String, on: Bool) {
        guard let g = groups.firstIndex(where: { $0.id == groupID }) else { return }
        for i in groups[g].items.indices { groups[g].items[i].isSelected = on }
    }

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
}

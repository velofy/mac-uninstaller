import Foundation
import SwiftUI
import UninstallerCore

@MainActor
final class AppsViewModel: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var isScanning = false
    @Published var query = ""

    @Published var selected: InstalledApp?
    @Published var leftovers: [RemovableItem] = []
    @Published var isInspecting = false
    @Published var statusMessage: String?

    private let libraryRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library", isDirectory: true)
    private let sizer = SizeCalculator()

    var filteredApps: [InstalledApp] {
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var selectedItems: [RemovableItem] { leftovers.filter(\.isSelected) }
    var selectedCount: Int { selectedItems.count }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + ($1.sizeBytes ?? 0) } }

    // MARK: - Scanning

    func loadApps() async {
        isScanning = true
        defer { isScanning = false }
        let found = await Task.detached { AppScanner().scan() }.value
        apps = found
        await fillAppSizes()
    }

    private func fillAppSizes() async {
        let urls = apps.map(\.bundleURL)
        let sizer = self.sizer
        let sizes = await Task.detached { await sizer.sizes(of: urls) }.value
        for i in apps.indices {
            apps[i].sizeBytes = sizes[apps[i].bundleURL]
        }
    }

    // MARK: - Selection

    func select(_ app: InstalledApp) async {
        selected = app
        statusMessage = nil
        await inspect(appURL: app.bundleURL, bundleID: app.bundleID, name: app.name)
    }

    /// Handle a `.app` dropped onto the window.
    func selectDropped(url: URL) async {
        guard url.pathExtension == "app" else { return }
        let std = url.standardizedFileURL
        let bundleID = AppScanner.bundleID(of: std)
        let name = std.deletingPathExtension().lastPathComponent
        let app = InstalledApp(bundleURL: std, name: name, bundleID: bundleID)
        selected = app
        statusMessage = nil
        await inspect(appURL: std, bundleID: bundleID, name: name)
    }

    private func inspect(appURL: URL, bundleID: String?, name: String) async {
        isInspecting = true
        defer { isInspecting = false }
        let root = libraryRoot
        var items = await Task.detached {
            LeftoverFinder().find(appURL: appURL, bundleID: bundleID, appName: name, libraryRoot: root)
        }.value
        leftovers = items                       // render immediately, sizes stream in

        let urls = items.map(\.url)
        let sizer = self.sizer
        let sizes = await Task.detached { await sizer.sizes(of: urls) }.value
        for i in items.indices { items[i].sizeBytes = sizes[items[i].url] }
        leftovers = items
    }

    // MARK: - Toggles

    func toggle(_ item: RemovableItem) {
        guard let i = leftovers.firstIndex(where: { $0.id == item.id }) else { return }
        leftovers[i].isSelected.toggle()
    }

    func setAll(_ on: Bool) {
        for i in leftovers.indices { leftovers[i].isSelected = on }
    }

    // MARK: - Removal

    func uninstall() async {
        let items = selectedItems
        guard !items.isEmpty else { return }
        let urls = items.map(\.url)
        let results = await Task.detached { Remover().trash(urls) }.value
        let ok = results.filter(\.succeeded).count
        let failed = results.count - ok

        statusMessage = failed == 0
            ? "Moved \(ok) item\(ok == 1 ? "" : "s") to the Trash."
            : "Moved \(ok) to the Trash, \(failed) could not be removed (permission)."

        selected = nil
        leftovers = []
        await loadApps()
    }
}

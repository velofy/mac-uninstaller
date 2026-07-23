import SwiftUI
import UninstallerCore

struct AppsView: View {
    @ObservedObject var vm: AppsViewModel
    @State private var confirming = false

    var body: some View {
        HSplitView {
            appList
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
            detail
                .frame(minWidth: 460, maxWidth: .infinity)
        }
    }

    // MARK: - Left: installed apps

    private var appList: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps", text: $vm.query)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            Divider()

            if vm.isScanning && vm.apps.isEmpty {
                Spacer(); ProgressView("Scanning apps…").controlSize(.small); Spacer()
            } else {
                List(vm.filteredApps, selection: Binding(
                    get: { vm.selected?.id },
                    set: { id in
                        if let app = vm.apps.first(where: { $0.id == id }) {
                            Task { await vm.select(app) }
                        }
                    }
                )) { app in
                    HStack(spacing: 10) {
                        FileIcon(url: app.bundleURL, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name).font(.system(size: 13)).lineLimit(1)
                            Text(app.bundleID ?? "no bundle id")
                                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(Format.size(app.sizeBytes))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .tag(app.id)
                }
                .listStyle(.inset)
            }
        }
        .background(.background)
    }

    // MARK: - Right: leftovers for the selected app

    private var detail: some View {
        ZStack {
            if vm.selected == nil {
                dropPrompt
            } else {
                selectedDetail
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            if let url = urls.first(where: { $0.pathExtension == "app" }) {
                Task { await vm.selectDropped(url: url) }
                return true
            }
            return false
        }
    }

    private var dropPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.app").font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("Select an app, or drop a .app here")
                .font(.system(size: 14)).foregroundStyle(.secondary)
            if let msg = vm.statusMessage {
                Text(msg).font(.system(size: 12)).foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedDetail: some View {
        VStack(spacing: 0) {
            if let app = vm.selected {
                HStack(spacing: 12) {
                    FileIcon(url: app.bundleURL, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.system(size: 17, weight: .semibold))
                        Text(app.bundleID ?? "no bundle id")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if vm.isInspecting { ProgressView().controlSize(.small) }
                }
                .padding(16)
                Divider()
            }

            HStack {
                Text("\(vm.leftovers.count) item\(vm.leftovers.count == 1 ? "" : "s") found")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Select all") { vm.setAll(true) }.controlSize(.small)
                Button("None") { vm.setAll(false) }.controlSize(.small)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            List {
                ForEach(groupedCategories, id: \.self) { category in
                    Section(category) {
                        ForEach(vm.leftovers.filter { $0.category == category }) { item in
                            ItemRow(item: item) { vm.toggle(item) }
                        }
                    }
                }
            }
            .listStyle(.inset)

            Divider()
            ActionBar(count: vm.selectedCount, bytes: vm.selectedBytes,
                      title: "Uninstall", enabled: vm.selectedCount > 0) {
                confirming = true
            }
        }
        .confirmationDialog(
            "Move \(vm.selectedCount) item\(vm.selectedCount == 1 ? "" : "s") to the Trash?",
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { Task { await vm.uninstall() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(Format.size(vm.selectedBytes)) will be reclaimed when you empty the Trash. Everything can be restored until then.")
        }
    }

    private var groupedCategories: [String] {
        var seen = Set<String>(); var order: [String] = []
        for item in vm.leftovers where !seen.contains(item.category) {
            seen.insert(item.category); order.append(item.category)
        }
        return order
    }
}

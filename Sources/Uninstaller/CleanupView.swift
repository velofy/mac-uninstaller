import SwiftUI
import UninstallerCore

struct CleanupView: View {
    @ObservedObject var vm: CleanupViewModel
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
            Divider()
            ActionBar(count: vm.selectedCount, bytes: vm.selectedBytes,
                      title: "Clean Up", enabled: vm.selectedCount > 0) {
                confirming = true
            }
        }
        .task { if !vm.hasScanned { await vm.scan() } }
        .confirmationDialog(
            "Move \(vm.selectedCount) item\(vm.selectedCount == 1 ? "" : "s") to the Trash?",
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { Task { await vm.clean() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(Format.size(vm.selectedBytes)) will be reclaimed when you empty the Trash. Everything can be restored until then.")
        }
    }

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Cleanup").font(.system(size: 13, weight: .semibold))
                Text(vm.hasScanned
                     ? "\(Format.size(vm.reclaimableBytes)) reclaimable"
                     : "Scan to find reclaimable space")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if let msg = vm.statusMessage {
                Text(msg).font(.system(size: 11)).foregroundStyle(.green)
            }
            Button {
                Task { await vm.scan() }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(vm.isScanning)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    @ViewBuilder private var content: some View {
        if vm.isScanning && vm.groups.allSatisfy(\.items.isEmpty) {
            Spacer(); ProgressView("Scanning…").controlSize(.small); Spacer()
        } else {
            List {
                ForEach(vm.groups) { group in
                    Section {
                        if group.items.isEmpty {
                            Text("Nothing found").font(.system(size: 12)).foregroundStyle(.tertiary)
                        } else {
                            ForEach(group.items) { item in
                                ItemRow(item: item) { vm.toggle(item) }
                            }
                        }
                    } header: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(group.title).font(.system(size: 12, weight: .semibold))
                                Text(group.subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Format.size(group.totalBytes == 0 ? nil : group.totalBytes))
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                            if !group.items.isEmpty {
                                Button("All") { vm.setGroup(group.id, on: true) }.controlSize(.mini)
                                Button("None") { vm.setGroup(group.id, on: false) }.controlSize(.mini)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

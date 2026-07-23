import SwiftUI
import AppKit
import UninstallerCore

/// The real Finder icon for a file/app URL.
struct FileIcon: View {
    let url: URL
    var size: CGFloat = 32

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .frame(width: size, height: size)
    }
}

/// A checkbox row for a removable item.
struct ItemRow: View {
    let item: RemovableItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { item.isSelected }, set: { _ in onToggle() }))
                .labelsHidden()
                .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.confidence == .name {
                    Text("name match — verify before removing")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            Text(Format.size(item.sizeBytes))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }
}

/// Sticky footer action bar with a total and a destructive button.
struct ActionBar: View {
    let count: Int
    let bytes: Int64
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count) selected")
                    .font(.system(size: 12, weight: .medium))
                Text(Format.size(bytes == 0 ? nil : bytes) == "…" ? "—" : Format.size(bytes))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: action) {
                Text(title).frame(minWidth: 120)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

import SwiftUI
import AppKit
import UninstallerCore

/// Flat badge colors per risk level. Solids chosen for >= 4.5:1 contrast with
/// white badge text (WCAG AA), no gradients anywhere.
extension RiskLevel {
    var uiColor: Color {
        switch self {
        case .easy: return Color(red: 0.12, green: 0.48, blue: 0.24)   // green
        case .review: return Color(red: 0.60, green: 0.36, blue: 0.00) // amber
        case .tough: return Color(red: 0.75, green: 0.22, blue: 0.17)  // red
        }
    }

    var badgeText: String { rawValue.uppercased() }
}

/// Color-coded risk badge: green easy, amber review, red tough.
struct RiskBadge: View {
    let risk: RiskLevel

    var body: some View {
        Text(risk.badgeText)
            .font(.system(size: 8.5, weight: .bold))
            .kerning(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(risk.uiColor, in: RoundedRectangle(cornerRadius: 3))
            .help(risk.defaultReason)
    }
}

/// Header strip splitting reclaimable space into Easy / Review / Tough totals.
struct RiskSummaryBar: View {
    let summary: RiskSummary

    var body: some View {
        HStack(spacing: 12) {
            pill("Easy", summary.easyBytes, RiskLevel.easy.uiColor)
            pill("Review", summary.reviewBytes, RiskLevel.review.uiColor)
            pill("Tough", summary.toughBytes, RiskLevel.tough.uiColor)
        }
    }

    private func pill(_ title: String, _ bytes: Int64, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.system(size: 10, weight: .medium))
            Text(Format.size(bytes))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

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

/// A checkbox row for a removable item, with its risk badge and, for anything
/// above easy, the human reason.
struct ItemRow: View {
    let item: RemovableItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { item.isSelected }, set: { _ in onToggle() }))
                .labelsHidden()
                .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.label)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    RiskBadge(risk: item.risk)
                }
                if item.risk != .easy {
                    Text(item.riskReason)
                        .font(.system(size: 10))
                        .foregroundStyle(item.risk.uiColor)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let age = Format.age(item.modifiedAt) {
                Text(age)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
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
                Text(Format.size(bytes))
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

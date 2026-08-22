import Foundation
import UninstallerCore

enum Format {
    static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f
    }()

    static let memoryFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        return f
    }()

    static func size(_ bytes: Int64?) -> String {
        guard let bytes else { return "…" }
        if bytes == 0 { return "0 KB" }
        return byteFormatter.string(fromByteCount: bytes)
    }

    static func memory(_ bytes: Int64?) -> String {
        guard let bytes else { return "…" }
        return memoryFormatter.string(fromByteCount: bytes)
    }

    /// Compact last-modified age for big-file rows: "today", "12d", "5mo", "2y".
    static func age(_ date: Date?) -> String? {
        guard let date else { return nil }
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        if days < 1 { return "today" }
        if days < 30 { return "\(days)d old" }
        if days < 365 { return "\(days / 30)mo old" }
        return "\(days / 365)y old"
    }
}

/// Builds the pre-removal confirmation text. Any selected TOUGH item is listed
/// explicitly, with its reason, before anything moves.
enum ConfirmText {
    static func removalMessage(items: [RemovableItem], bytes: Int64) -> String {
        var lines = [
            "\(Format.size(bytes)) will be reclaimed when you empty the Trash. Everything can be restored until then.",
        ]
        let tough = items.filter { $0.risk == .tough }
        if !tough.isEmpty {
            lines.append("")
            lines.append("Hard-to-undo items selected:")
            for item in tough {
                lines.append("• \(item.label): \(item.riskReason)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

import Foundation

enum Format {
    static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f
    }()

    static func size(_ bytes: Int64?) -> String {
        guard let bytes else { return "…" }
        if bytes == 0 { return "—" }
        return byteFormatter.string(fromByteCount: bytes)
    }
}

import Foundation

/// A local APFS Time Machine snapshot, as reported by `tmutil`.
public struct TimeMachineSnapshot: Identifiable, Sendable, Equatable {
    public var id: String { name }
    /// Full snapshot name, e.g. `com.apple.TimeMachine.2026-08-21-104512.local`.
    public let name: String
    /// The date token `tmutil deletelocalsnapshots` takes, e.g. `2026-08-21-104512`.
    public let dateToken: String

    public init(name: String, dateToken: String) {
        self.name = name
        self.dateToken = dateToken
    }
}

/// Lists and deletes local APFS Time Machine snapshots via `/usr/bin/tmutil`.
///
/// Safety rationale: snapshot deletion is the one storage operation that CANNOT
/// go through the Trash; it is irreversible the moment tmutil runs. The UI must
/// therefore put it behind its own explicit confirmation, and this type refuses
/// to pass anything but a strictly validated date token to tmutil, so no other
/// argument can ever reach the tool. Parsing is pure and covered by corecheck.
public struct SnapshotManager: Sendable {
    public init() {}

    private static let tmutilPath = "/usr/bin/tmutil"
    private static let namePrefix = "com.apple.TimeMachine."
    private static let nameSuffix = ".local"

    // MARK: - Pure parsing (testable)

    /// Parse `tmutil listlocalsnapshots /` output. Non-snapshot lines (the
    /// "Snapshots for disk" header, malformed names) are skipped.
    public static func parseList(_ output: String) -> [TimeMachineSnapshot] {
        var snapshots: [TimeMachineSnapshot] = []
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix(namePrefix) else { continue }
            var token = String(line.dropFirst(namePrefix.count))
            if token.hasSuffix(nameSuffix) {
                token = String(token.dropLast(nameSuffix.count))
            }
            guard isValidDateToken(token) else { continue }
            snapshots.append(TimeMachineSnapshot(name: line, dateToken: token))
        }
        return snapshots
    }

    /// True only for the exact `YYYY-MM-DD-HHMMSS` shape tmutil emits. This is
    /// the in-code guard that keeps arbitrary strings out of the tmutil argv.
    public static func isValidDateToken(_ token: String) -> Bool {
        let parts = token.split(separator: "-", omittingEmptySubsequences: false)
        let lengths = [4, 2, 2, 6]
        guard parts.count == lengths.count else { return false }
        for (part, length) in zip(parts, lengths) {
            guard part.count == length,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        }
        return true
    }

    // MARK: - tmutil (blocking; call off the main actor)

    /// List local snapshots of the root volume. Returns [] when tmutil is
    /// unavailable or errors.
    public func list() -> [TimeMachineSnapshot] {
        guard let result = Self.run(["listlocalsnapshots", "/"]) else { return [] }
        guard result.status == 0 else { return [] }
        return Self.parseList(result.stdout)
    }

    /// Delete one local snapshot by date token. IRREVERSIBLE: this does not go
    /// to the Trash. Runs as the current user, never with sudo.
    public func deleteSnapshot(dateToken: String) -> (succeeded: Bool, message: String) {
        guard Self.isValidDateToken(dateToken) else {
            return (false, "Refusing to run tmutil with an unexpected token.")
        }
        guard let result = Self.run(["deletelocalsnapshots", dateToken]) else {
            return (false, "tmutil is not available on this system.")
        }
        if result.status == 0 {
            return (true, "Deleted local snapshot \(dateToken).")
        }
        let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return (false, err.isEmpty ? "tmutil exited with status \(result.status)." : err)
    }

    private static func run(_ args: [String]) -> (status: Int32, stdout: String, stderr: String)? {
        guard FileManager.default.isExecutableFile(atPath: tmutilPath) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmutilPath)
        process.arguments = args
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do { try process.run() } catch { return nil }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? ""
        )
    }
}

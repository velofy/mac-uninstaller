import Foundation

/// Outcome of a memory-pressure run.
public struct MemoryRelief: Sendable, Equatable {
    public let ran: Bool
    /// Change in free memory measured across the run; nil when it could not be
    /// measured. Can legitimately be tiny or zero: that is reported honestly.
    public let freedBytes: Int64?
    public let message: String

    public init(ran: Bool, freedBytes: Int64?, message: String) {
        self.ran = ran
        self.freedBytes = freedBytes
        self.message = message
    }
}

/// Frees reclaimable memory by briefly running
/// `/usr/bin/memory_pressure -l warn` as the current user.
///
/// Safety and honesty rationale:
/// - No sudo, no root escalation, ever. Warn-level pressure only makes apps
///   shed caches and purgeable allocations and lets the compressor reclaim
///   idle pages. Without root it cannot purge the kernel file cache and cannot
///   touch wired memory.
/// - The ONLY process this type ever signals is the `memory_pressure` child it
///   spawned itself (SIGINT so the tool releases its pages and exits cleanly).
///   It never signals or kills any other process.
public struct MemoryReliever: Sendable {
    public init() {}

    private static let toolPath = "/usr/bin/memory_pressure"

    /// Apply warn-level pressure for about `duration` seconds, then stop the
    /// child and report the measured change in free memory.
    public func relieve(duration: TimeInterval = 8) async -> MemoryRelief {
        guard FileManager.default.isExecutableFile(atPath: Self.toolPath) else {
            return MemoryRelief(ran: false, freedBytes: nil,
                                message: "memory_pressure is not available on this system.")
        }

        let before = MemoryStatsReader().snapshot()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.toolPath)
        process.arguments = ["-l", "warn"]
        // The tool's chatter is irrelevant; null devices also mean its output
        // can never block on a full pipe.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return MemoryRelief(ran: false, freedBytes: nil,
                                message: "Could not start memory_pressure: \(error.localizedDescription)")
        }

        // Hold pressure briefly. If our task is cancelled we fall through and
        // stop the child right away; it is never left running.
        let end = Date().addingTimeInterval(duration)
        while process.isRunning && Date() < end && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if process.isRunning { process.interrupt() }    // SIGINT to our own child only
        let hardEnd = Date().addingTimeInterval(3)
        while process.isRunning && Date() < hardEnd {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if process.isRunning { process.terminate() }    // still our own child only

        // Let the freed pages settle before measuring.
        try? await Task.sleep(nanoseconds: 500_000_000)
        let after = MemoryStatsReader().snapshot()

        guard let before, let after else {
            return MemoryRelief(ran: true, freedBytes: nil,
                                message: "Pressure applied; the change could not be measured.")
        }
        let freed = after.freeBytes - before.freeBytes
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        if freed > 0 {
            return MemoryRelief(ran: true, freedBytes: freed,
                                message: "Free memory grew by \(formatter.string(fromByteCount: freed)).")
        }
        return MemoryRelief(ran: true, freedBytes: freed,
                            message: "No measurable change: memory was already as free as warn-level pressure can make it.")
    }
}

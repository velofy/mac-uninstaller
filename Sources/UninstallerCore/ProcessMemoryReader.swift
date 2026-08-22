import Foundation
import Darwin

/// One process's memory usage, read via libproc.
public struct ProcessMemoryInfo: Identifiable, Sendable, Equatable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    /// Physical footprint (what Activity Monitor's Memory column shows).
    public let footprintBytes: Int64
    /// Classic resident set size.
    public let residentBytes: Int64

    public init(pid: Int32, name: String, footprintBytes: Int64, residentBytes: Int64) {
        self.pid = pid
        self.name = name
        self.footprintBytes = footprintBytes
        self.residentBytes = residentBytes
    }
}

/// Lists the processes using the most memory, via `proc_listallpids` +
/// `proc_pid_rusage`. Read-only: it never signals, pauses, or kills anything.
/// Processes this user cannot inspect (root daemons, other users) are skipped
/// silently; that is a permission boundary, not an error.
public struct ProcessMemoryReader: Sendable {
    public init() {}

    /// The top `limit` inspectable processes, sorted by physical footprint,
    /// largest first.
    public func topByMemory(limit: Int = 15) -> [ProcessMemoryInfo] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }

        // Headroom for processes spawned between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 64)
        let filled = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress,
                             Int32(buffer.count * MemoryLayout<pid_t>.stride))
        }
        guard filled > 0 else { return [] }

        var infos: [ProcessMemoryInfo] = []
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            var usage = rusage_info_v4()
            let ok = withUnsafeMutablePointer(to: &usage) { pointer -> Int32 in
                pointer.withMemoryRebound(to: (rusage_info_t?).self, capacity: 1) { reboundPointer in
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, reboundPointer)
                }
            }
            guard ok == 0 else { continue }     // not inspectable by this user
            infos.append(ProcessMemoryInfo(
                pid: pid,
                name: Self.name(of: pid),
                footprintBytes: Int64(bitPattern: usage.ri_phys_footprint),
                residentBytes: Int64(bitPattern: usage.ri_resident_size)
            ))
        }
        let sorted = infos.sorted { $0.footprintBytes > $1.footprintBytes }
        return Array(sorted.prefix(max(0, limit)))
    }

    static func name(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        if length > 0 { return String(cString: buffer) }
        return "pid \(pid)"
    }
}

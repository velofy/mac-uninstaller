import Foundation
import Darwin

/// A point-in-time picture of system memory, in bytes.
public struct MemorySnapshot: Sendable, Equatable {
    public let totalBytes: Int64
    public let freeBytes: Int64
    public let activeBytes: Int64
    public let inactiveBytes: Int64
    public let wiredBytes: Int64
    public let compressedBytes: Int64
    public let purgeableBytes: Int64
    public let swapUsedBytes: Int64
    public let swapTotalBytes: Int64

    public init(
        totalBytes: Int64, freeBytes: Int64, activeBytes: Int64,
        inactiveBytes: Int64, wiredBytes: Int64, compressedBytes: Int64,
        purgeableBytes: Int64, swapUsedBytes: Int64, swapTotalBytes: Int64
    ) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.activeBytes = activeBytes
        self.inactiveBytes = inactiveBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.purgeableBytes = purgeableBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
    }

    /// The Activity-Monitor-style "memory used" figure.
    public var usedBytes: Int64 { activeBytes + wiredBytes + compressedBytes }
}

/// Reads live memory statistics from the Mach host APIs
/// (`host_statistics64` with `HOST_VM_INFO64`, `host_page_size`) plus sysctl
/// for the physical total and swap usage. Read-only: nothing here can change
/// system state.
public struct MemoryStatsReader: Sendable {
    public init() {}

    public func snapshot() -> MemorySnapshot? {
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        let page = Int64(pageSize)

        var totalBytes: Int64 = 0
        var totalSize = MemoryLayout<Int64>.size
        sysctlbyname("hw.memsize", &totalBytes, &totalSize, nil, 0)

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)

        return MemorySnapshot(
            totalBytes: totalBytes,
            freeBytes: Int64(stats.free_count) * page,
            activeBytes: Int64(stats.active_count) * page,
            inactiveBytes: Int64(stats.inactive_count) * page,
            wiredBytes: Int64(stats.wire_count) * page,
            compressedBytes: Int64(stats.compressor_page_count) * page,
            purgeableBytes: Int64(stats.purgeable_count) * page,
            swapUsedBytes: Int64(swap.xsu_used),
            swapTotalBytes: Int64(swap.xsu_total)
        )
    }
}

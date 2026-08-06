import Foundation
import IOKit

/// Apple Silicon GPU utilization + GPU-mapped memory via AGXAccelerator PerformanceStatistics.
///
/// Limitation: requires AGX (Apple GPU). Intel / discrete GPUs return nil.
/// Utilization is the driver's instantaneous "Device Utilization %", not a
/// power-weighted IOReport histogram. Memory is unified-RAM bytes mapped to
/// the GPU (`Alloc system memory`) over physical DRAM.
enum GPUMetricsSampler {
    struct Snapshot {
        /// 0...1
        var utilization: Double
        /// GPU-mapped bytes (Alloc system memory).
        var memoryUsedBytes: UInt64
        var memoryTotalBytes: UInt64
        /// 0...1 of physical DRAM.
        var memoryFraction: Double
    }

    private static var cachedService: io_service_t = 0
    private static var cacheLookupFailed = false

    static func sample() -> Snapshot? {
        guard let stats = readPerformanceStatistics() else { return nil }

        let utilPercent = doubleValue(stats["Device Utilization %"])
            ?? doubleValue(stats["Renderer Utilization %"])
            ?? 0
        let alloc = uint64Value(stats["Alloc system memory"]) ?? 0
        let total = physicalMemoryBytes()
        guard total > 0 else { return nil }

        return Snapshot(
            utilization: min(max(utilPercent / 100.0, 0), 1),
            memoryUsedBytes: alloc,
            memoryTotalBytes: total,
            memoryFraction: min(max(Double(alloc) / Double(total), 0), 1)
        )
    }

    // MARK: - IOKit

    private static func acceleratorService() -> io_service_t? {
        if cachedService != 0 {
            return cachedService
        }
        if cacheLookupFailed {
            return nil
        }

        let matching = IOServiceMatching("AGXAccelerator")
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else {
            cacheLookupFailed = true
            return nil
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else {
            cacheLookupFailed = true
            return nil
        }
        // Retain for the process lifetime; release leftovers from the iterator.
        var next = IOIteratorNext(iterator)
        while next != 0 {
            IOObjectRelease(next)
            next = IOIteratorNext(iterator)
        }
        cachedService = service
        return service
    }

    private static func readPerformanceStatistics() -> [String: Any]? {
        guard let service = acceleratorService() else { return nil }
        guard let props = copyProperties(service) else {
            // Service may have gone away; clear cache and retry once next tick.
            IOObjectRelease(cachedService)
            cachedService = 0
            return nil
        }
        return props["PerformanceStatistics"] as? [String: Any]
    }

    private static func copyProperties(_ service: io_registry_entry_t) -> [String: Any]? {
        var cfProps: Unmanaged<CFMutableDictionary>?
        let kr = IORegistryEntryCreateCFProperties(service, &cfProps, kCFAllocatorDefault, 0)
        guard kr == KERN_SUCCESS, let dict = cfProps?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return dict
    }

    private static func physicalMemoryBytes() -> UInt64 {
        UInt64(ProcessInfo.processInfo.physicalMemory)
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        switch any {
        case let n as NSNumber: return n.doubleValue
        case let i as Int: return Double(i)
        case let d as Double: return d
        case let f as Float: return Double(f)
        default: return nil
        }
    }

    private static func uint64Value(_ any: Any?) -> UInt64? {
        switch any {
        case let n as NSNumber: return n.uint64Value
        case let i as Int: return UInt64(i)
        case let u as UInt64: return u
        case let i64 as Int64: return UInt64(max(0, i64))
        default: return nil
        }
    }
}

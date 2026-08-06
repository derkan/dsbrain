import Darwin
import Foundation

/// Host (system) RAM usage via `host_statistics64`, not GPU-mapped alloc.
enum SystemMemorySampler {
    /// Activity Monitor–style memory pressure (`kern.memorystatus_vm_pressure_level`).
    enum Pressure: Equatable {
        case normal
        case warning
        case critical

        /// Maps sysctl `kern.memorystatus_vm_pressure_level` (0/1/2; some builds use 4 for critical).
        static func fromSysctlLevel(_ level: Int32) -> Pressure {
            switch level {
            case 0: return .normal
            case 1: return .warning
            default: return .critical
            }
        }

        var label: String {
            switch self {
            case .normal: return "normal"
            case .warning: return "warning"
            case .critical: return "critical"
            }
        }
    }

    struct Snapshot {
        var usedBytes: UInt64
        var totalBytes: UInt64
        /// 0...1 of physical DRAM.
        var usedFraction: Double
        var pressure: Pressure
    }

    static func sample() -> Snapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        let usedPages =
            UInt64(stats.active_count)
            + UInt64(stats.inactive_count)
            + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)
        let usedBytes = usedPages * pageSize
        let totalBytes = UInt64(ProcessInfo.processInfo.physicalMemory)
        guard totalBytes > 0 else { return nil }

        return Snapshot(
            usedBytes: usedBytes,
            totalBytes: totalBytes,
            usedFraction: min(max(Double(usedBytes) / Double(totalBytes), 0), 1),
            pressure: currentPressure()
        )
    }

    static func currentPressure() -> Pressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let rc = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        guard rc == 0 else { return .normal }
        return Pressure.fromSysctlLevel(level)
    }
}

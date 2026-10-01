import Foundation
import Observation
import Darwin

@Observable @MainActor
final class SystemMonitorService {
    static let shared = SystemMonitorService()

    var cpuUsagePercent: Double = 0.0
    var memoryUsedGB: Double = 0.0
    var memoryTotalGB: Double = 0.0
    var memoryUsagePercent: Double = 0.0
    var diskFreeGB: Double = 0.0

    private var timer: Timer?

    private init() {
        refresh()
        startMonitoring()
    }

    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    func refresh() {
        updateMemory()
        updateDisk()
        updateCPU()
    }

    private func updateMemory() {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        self.memoryTotalGB = Double(physicalMemory) / 1_073_741_824.0

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let kerr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let pageSize = UInt64(getpagesize())
            let active = UInt64(stats.active_count) * pageSize
            let wired = UInt64(stats.wire_count) * pageSize
            let compressed = UInt64(stats.compressor_page_count) * pageSize
            let usedBytes = active + wired + compressed
            self.memoryUsedGB = Double(usedBytes) / 1_073_741_824.0
            self.memoryUsagePercent = min(100.0, (self.memoryUsedGB / self.memoryTotalGB) * 100.0)
        }
    }

    private func updateDisk() {
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
           let freeSize = attrs[.systemFreeSize] as? NSNumber {
            self.diskFreeGB = Double(freeSize.int64Value) / 1_073_741_824.0
        }
    }

    private func updateCPU() {
        // Sample host CPU load
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let kerr = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let user = Double(cpuLoad.cpu_ticks.0)
            let system = Double(cpuLoad.cpu_ticks.1)
            let idle = Double(cpuLoad.cpu_ticks.2)
            let nice = Double(cpuLoad.cpu_ticks.3)
            let total = user + system + idle + nice
            if total > 0 {
                let active = user + system + nice
                self.cpuUsagePercent = min(100.0, (active / total) * 100.0)
            }
        }
    }
}

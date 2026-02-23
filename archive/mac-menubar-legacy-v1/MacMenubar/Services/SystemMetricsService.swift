import Combine
import Foundation
import IOKit.ps
import Darwin.Mach

final class SystemMetricsService: MetricsProviding {
    var metricsPublisher: AnyPublisher<SystemMetrics, Never> {
        subject.eraseToAnyPublisher()
    }

    private let subject = CurrentValueSubject<SystemMetrics, Never>(.zero)
    private let queue = DispatchQueue(label: "macmenubar.metrics", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var previousCPULoad: CPULoad?

    func start() {
        guard timer == nil else { return }

        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .seconds(2), leeway: .milliseconds(250))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let metrics = self.collectMetrics()
            self.subject.send(metrics)
        }
        source.resume()
        timer = source
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func collectMetrics() -> SystemMetrics {
        SystemMetrics(
            batteryPercentage: currentBatteryPercentage(),
            cpuUsage: currentCPUUsage(),
            memoryUsage: currentMemoryUsage()
        )
    }

    private func currentBatteryPercentage() -> Int {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
            let source = sources.first,
            let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
            let current = info[kIOPSCurrentCapacityKey as String] as? Int,
            let maxCapacity = info[kIOPSMaxCapacityKey as String] as? Int,
            maxCapacity > 0
        else {
            return subject.value.batteryPercentage
        }

        return Swift.max(0, Swift.min(100, (current * 100) / maxCapacity))
    }

    private func currentCPUUsage() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)

        let status: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebounded in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebounded, &count)
            }
        }

        guard status == KERN_SUCCESS else {
            return subject.value.cpuUsage
        }

        let currentLoad = CPULoad(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )

        defer { previousCPULoad = currentLoad }
        guard let previousCPULoad else {
            return subject.value.cpuUsage
        }

        let userDiff = currentLoad.user &- previousCPULoad.user
        let systemDiff = currentLoad.system &- previousCPULoad.system
        let idleDiff = currentLoad.idle &- previousCPULoad.idle
        let niceDiff = currentLoad.nice &- previousCPULoad.nice

        let total = Double(userDiff + systemDiff + idleDiff + niceDiff)
        guard total > 0 else {
            return subject.value.cpuUsage
        }

        let used = Double(userDiff + systemDiff + niceDiff)
        return max(0, min(100, (used / total) * 100))
    }

    private func currentMemoryUsage() -> Double {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let status: kern_return_t = withUnsafeMutablePointer(to: &vmStats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebounded in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebounded, &count)
            }
        }

        guard status == KERN_SUCCESS else {
            return subject.value.memoryUsage
        }

        var hostPageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &hostPageSize)
        let pageSize = Double(hostPageSize)
        let active = Double(vmStats.active_count) * pageSize
        let inactive = Double(vmStats.inactive_count) * pageSize
        let wired = Double(vmStats.wire_count) * pageSize
        let compressed = Double(vmStats.compressor_page_count) * pageSize
        let used = active + inactive + wired + compressed
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else {
            return subject.value.memoryUsage
        }

        return max(0, min(100, (used / total) * 100))
    }
}

private struct CPULoad {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64
}

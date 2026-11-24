import Darwin
import Foundation

// MARK: - CPU

struct CPUUsage {
    var total: Double = 0   // 0...1
    var user: Double = 0
    var system: Double = 0
}

/// Whole-machine CPU load from the kernel's cumulative tick counters (all cores combined).
final class CPUSampler {
    private let host = mach_host_self()
    private var previous: host_cpu_load_info?

    /// Returns nil on the first call (needs two readings to compute a delta).
    func sample() -> CPUUsage? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        defer { previous = info }
        guard let prev = previous else { return nil }

        // Tick counters are UInt32 and wrap; wrapping subtraction keeps the delta correct.
        let user = Double(info.cpu_ticks.0 &- prev.cpu_ticks.0)    // CPU_STATE_USER
        let system = Double(info.cpu_ticks.1 &- prev.cpu_ticks.1)  // CPU_STATE_SYSTEM
        let idle = Double(info.cpu_ticks.2 &- prev.cpu_ticks.2)    // CPU_STATE_IDLE
        let nice = Double(info.cpu_ticks.3 &- prev.cpu_ticks.3)    // CPU_STATE_NICE
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return CPUUsage(
            total: (user + system + nice) / total,
            user: (user + nice) / total,
            system: system / total)
    }
}

// MARK: - Memory

struct MemoryUsage {
    var used: UInt64 = 0
    var total: UInt64 = ProcessInfo.processInfo.physicalMemory
    var fraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
}

/// "Memory Used" as Activity Monitor defines it: app memory + wired + compressed.
final class MemorySampler {
    private let host = mach_host_self()
    private let pageSize: UInt64
    private let total = ProcessInfo.processInfo.physicalMemory

    init() {
        var size: vm_size_t = 0
        host_page_size(host, &size)
        pageSize = UInt64(size)
    }

    func sample() -> MemoryUsage? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let anonymous = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let appPages = anonymous > purgeable ? anonymous - purgeable : 0
        let usedPages = appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return MemoryUsage(used: min(usedPages * pageSize, total), total: total)
    }
}

// MARK: - Network

struct NetworkRate {
    var down: Double = 0  // bytes per second
    var up: Double = 0
}

/// Throughput over physical interfaces (`en*`: Wi-Fi, Ethernet, USB/Thunderbolt adapters).
///
/// Reads 64-bit byte counters via `sysctl(NET_RT_IFLIST2)`; the `getifaddrs` counters are
/// 32-bit and wrap every 4 GB. Virtual interfaces (VPN `utun*`, `bridge*`, `awdl*`, `lo0`)
/// are skipped so tunnelled traffic is not counted twice.
final class NetworkSampler {
    private typealias Counters = [String: (rx: UInt64, tx: UInt64)]
    private var previous: Counters = [:]
    private var previousTime: TimeInterval?

    /// Returns nil on the first call (needs two readings to compute a rate).
    func sample() -> NetworkRate? {
        let now = ProcessInfo.processInfo.systemUptime
        guard let current = Self.readCounters() else { return nil }
        defer { previous = current; previousTime = now }
        guard let t0 = previousTime, now > t0 else { return nil }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        for (name, c) in current {
            guard let p = previous[name] else { continue }  // interface just appeared
            if c.rx >= p.rx { rx += c.rx - p.rx }           // counter reset: skip this tick
            if c.tx >= p.tx { tx += c.tx - p.tx }
        }
        let dt = now - t0
        return NetworkRate(down: Double(rx) / dt, up: Double(tx) / dt)
    }

    private static func readCounters() -> Counters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }

        var counters: Counters = [:]
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                defer { offset += Int(header.ifm_msglen) }

                guard Int32(header.ifm_type) == RTM_IFINFO2,
                      offset + MemoryLayout<if_msghdr2>.size <= length else { continue }
                let msg = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                guard msg.ifm_flags & IFF_UP != 0, msg.ifm_flags & IFF_LOOPBACK == 0,
                      if_indextoname(UInt32(msg.ifm_index), &name) != nil else { continue }
                let ifName = String(cString: name)
                guard ifName.hasPrefix("en") else { continue }
                counters[ifName] = (msg.ifm_data.ifi_ibytes, msg.ifm_data.ifi_obytes)
            }
        }
        return counters
    }
}

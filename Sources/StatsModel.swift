import Foundation

struct Snapshot {
    static let historyLength = 60

    var network = NetworkRate()
    var cpu = CPUUsage()
    var memory = MemoryUsage()

    // Newest sample last; grows up to `historyLength`, so charts never show invented zeros.
    var downHistory: [Double] = []
    var upHistory: [Double] = []
    var cpuHistory: [Double] = []
    var memoryHistory: [Double] = []
}

/// Samples once per second and publishes a single snapshot per tick (one SwiftUI update).
@MainActor
final class StatsModel: ObservableObject {
    @Published private(set) var snapshot = Snapshot()

    private let cpuSampler = CPUSampler()
    private let memorySampler = MemorySampler()
    private let networkSampler = NetworkSampler()
    private var timer: Timer?

    func start(interval: TimeInterval = 1) {
        guard timer == nil else { return }
        tick()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval * 0.1  // lets macOS coalesce wake-ups
        RunLoop.main.add(timer, forMode: .common)  // keep ticking while menus are tracking
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        var next = snapshot
        if let n = networkSampler.sample() {
            next.network = n
            Self.push(n.down, onto: &next.downHistory)
            Self.push(n.up, onto: &next.upHistory)
        }
        if let c = cpuSampler.sample() {
            next.cpu = c
            Self.push(c.total, onto: &next.cpuHistory)
        }
        if let m = memorySampler.sample() {
            next.memory = m
            Self.push(m.fraction, onto: &next.memoryHistory)
        }
        snapshot = next
    }

    private static func push(_ value: Double, onto history: inout [Double]) {
        history.append(value)
        if history.count > Snapshot.historyLength { history.removeFirst() }
    }
}

// MARK: - Formatting

enum Format {
    /// 4_200_000 -> ("4.2", "MB/s"). Decimal units, matching how ISPs and Activity Monitor count.
    static func rate(_ bytesPerSecond: Double) -> (value: String, unit: String) {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = max(bytesPerSecond, 0)
        var index = 0
        while value >= 999.5 && index < units.count - 1 {
            value /= 1000
            index += 1
        }
        let text = (index == 0 || value >= 99.95) ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return (text, units[index])
    }

    /// Bytes/s -> "33.6 Mbps" (how speed tests report).
    static func megabits(_ bytesPerSecond: Double) -> String {
        let mbps = bytesPerSecond * 8 / 1_000_000
        return mbps >= 100 ? String(format: "%.0f Mbps", mbps) : String(format: "%.1f Mbps", mbps)
    }

    /// Chart ceiling for a network history. Floored at 50 KB/s so idle chatter doesn't look like a spike.
    static func networkScale(_ history: [Double]) -> Double {
        max(history.max() ?? 0, 50_000)
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f", min(max(fraction, 0), 1) * 100)
    }

    static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / 1_073_741_824)
    }
}

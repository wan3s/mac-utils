import Foundation
import Observation

/// Samples CPU, memory and disk for the desktop widget. Runs only while the widget is visible.
@MainActor
@Observable
final class SystemMonitor {
    private(set) var cpu: CPUUsage?
    private(set) var coreLabels: [String] = []
    private(set) var loadAverage: [Double] = []
    private(set) var cpuTemperature: Double?
    private(set) var memory: MemoryUsage?
    private(set) var disk: DiskUsage?
    private(set) var ssdTemperature: Double?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let cpuSampler = CPUSampler()
    @ObservationIgnored private let diskSampler = DiskSampler()
    @ObservationIgnored private let temperatures = TemperatureSensors()
    @ObservationIgnored private var timer: Timer?

    var hasCPUTemperature: Bool { temperatures.hasCPUSensors }
    var hasSSDTemperature: Bool { temperatures.hasSSDSensors }

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isRunning: Bool { timer != nil }

    func start(interval: TimeInterval) {
        stop()
        tick()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        if settings.showCPU {
            if let usage = cpuSampler.sample() {
                if coreLabels.count != usage.cores.count {
                    coreLabels = CPUSampler.coreLabels(count: usage.cores.count)
                }
                cpu = usage
            }
            loadAverage = settings.showLoadAverage ? CPUSampler.loadAverage() : []
            cpuTemperature = settings.showCPUTemperature ? temperatures.cpuTemperature() : nil
        }
        if settings.showMemory {
            memory = MemorySampler.sample()
        }
        if settings.showDisk {
            disk = diskSampler.sample(volumePath: settings.diskVolumePath)
            ssdTemperature = settings.showSSDTemperature ? temperatures.ssdTemperature() : nil
        }
    }
}

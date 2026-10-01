import AppKit
import Observation

struct TrafficPoint: Identifiable {
    let id: Int
    let download: Double
    let upload: Double
}

/// Samples network throughput every second and keeps the public IP location up to date.
@MainActor
@Observable
final class NetworkMonitor {
    enum GeoStatus: Equatable {
        case idle
        case loading
        case failed
    }

    static let historyLength = 60

    private(set) var downloadRate: Double = 0
    private(set) var uploadRate: Double = 0
    private(set) var history: [TrafficPoint] = []
    private(set) var sessionReceived: UInt64 = 0
    private(set) var sessionSent: UInt64 = 0
    private(set) var local = LocalNetworkInfo()
    private(set) var geo: GeoInfo?
    private(set) var geoStatus: GeoStatus = .idle
    private(set) var geoUpdatedAt: Date?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let sampler = NetworkTrafficSampler()
    @ObservationIgnored private let infoProvider = NetworkInfoProvider()
    @ObservationIgnored private let geoService = GeoIPService()
    @ObservationIgnored private var sampleTimer: Timer?
    @ObservationIgnored private var geoTimer: Timer?
    @ObservationIgnored private var geoTask: Task<Void, Never>?
    @ObservationIgnored private var pendingGeoRefresh: DispatchWorkItem?
    @ObservationIgnored private var lastSampleTime: TimeInterval = 0
    @ObservationIgnored private var sampleIndex = 0
    /// Set after a network change: the current location may belong to the previous network.
    @ObservationIgnored private var geoIsStale = false

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        _ = sampler.delta()
        lastSampleTime = ProcessInfo.processInfo.systemUptime
        local = infoProvider.current()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        // Common mode keeps the menu bar ticking while a menu or popover is tracking.
        RunLoop.main.add(timer, forMode: .common)
        sampleTimer = timer

        refreshGeo()
        observeChanges { [weak self] in
            guard let self else { return }
            self.scheduleGeoTimer(minutes: self.settings.geoRefreshMinutes)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleGeoRefresh(after: 3, networkChanged: true) }
        }
    }

    /// Looks up the public IP location now, replacing any lookup in flight.
    func refreshGeo() {
        pendingGeoRefresh?.cancel()
        pendingGeoRefresh = nil
        geoTask?.cancel()
        guard local.isOnline else {
            geo = nil
            geoStatus = .failed
            return
        }
        geoStatus = .loading
        geoTask = Task { [weak self, geoService] in
            do {
                let info = try await geoService.lookup()
                guard !Task.isCancelled, let self else { return }
                self.geo = info
                self.geoUpdatedAt = Date()
                self.geoStatus = .idle
                self.geoIsStale = false
            } catch {
                guard !Task.isCancelled, let self else { return }
                if self.geoIsStale { self.geo = nil }
                self.geoStatus = .failed
                self.scheduleGeoRefresh(after: 30, networkChanged: false)
            }
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = max(now - lastSampleTime, 0.001)
        lastSampleTime = now

        let delta = sampler.delta()
        downloadRate = Double(delta.received) / elapsed
        uploadRate = Double(delta.sent) / elapsed
        sessionReceived += delta.received
        sessionSent += delta.sent

        sampleIndex += 1
        history.append(TrafficPoint(id: sampleIndex, download: downloadRate, upload: uploadRate))
        if history.count > Self.historyLength {
            history.removeFirst(history.count - Self.historyLength)
        }

        let info = infoProvider.current()
        if info.fingerprint != local.fingerprint {
            // Give routes a moment to settle after a VPN connects or Wi-Fi rejoins.
            scheduleGeoRefresh(after: 2, networkChanged: true)
        }
        if info != local { local = info }
    }

    private func scheduleGeoRefresh(after delay: TimeInterval, networkChanged: Bool) {
        if networkChanged { geoIsStale = true }
        pendingGeoRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refreshGeo() }
        }
        pendingGeoRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scheduleGeoTimer(minutes: Int) {
        geoTimer?.invalidate()
        let timer = Timer(timeInterval: TimeInterval(max(minutes, 1) * 60), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshGeo() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        geoTimer = timer
    }
}

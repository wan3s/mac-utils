import AppKit
import Charts
import SwiftUI

/// Details shown when the menu bar item is clicked.
struct NetworkPopoverView: View {
    let network: NetworkMonitor
    @Bindable var settings: AppSettings
    let actions: AppActions
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            details
            Divider()
            traffic
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 330)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            if network.local.isOnline, let geo = network.geo, let flag = geo.flag {
                Text(flag)
                    .font(.system(size: 40))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: network.local.isOnline ? "globe" : "wifi.slash")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if network.local.isVPNActive {
                Label("VPN", systemImage: "lock.shield.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(.green)
                    .background(Capsule().fill(.green.opacity(0.15)))
                    .help("A VPN connection is active")
            }
        }
    }

    private var title: String {
        if !network.local.isOnline { return String(localized: "No network connection") }
        if let geo = network.geo { return geo.countryName }
        if network.geoStatus == .failed { return String(localized: "Location unavailable") }
        return String(localized: "Determining location…")
    }

    private var subtitle: String? {
        guard network.local.isOnline else { return String(localized: "Connect to Wi-Fi or Ethernet.") }
        guard let geo = network.geo else {
            return network.geoStatus == .failed ? String(localized: "The location service didn't respond.") : nil
        }
        let place = [geo.city, geo.region].compactMap { $0 }.removingDuplicates().joined(separator: ", ")
        return place.isEmpty ? nil : place
    }

    // MARK: Details

    private var details: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            row("Public IP") {
                HStack(spacing: 4) {
                    Text(network.geo?.ip ?? "—").textSelection(.enabled)
                    if let ip = network.geo?.ip {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(ip, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy IP Address")
                        .accessibilityLabel("Copy IP Address")
                    }
                }
            }
            row("Provider") { Text(provider) }
            row("Time zone") { Text(network.geo?.timeZone ?? "—") }
            Divider().gridCellUnsizedAxes(.horizontal)
            row("Interface") { Text(interface) }
            row("Local IP") { Text(network.local.localAddress ?? "—").textSelection(.enabled) }
            row("VPN") { Text(vpn) }
        }
        .font(.callout)
    }

    private func row(_ label: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var provider: String {
        guard let geo = network.geo else { return "—" }
        return [geo.provider, geo.asn.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ").nonEmptyOrDash
    }

    private var interface: String {
        guard let name = network.local.interfaceName else { return "—" }
        guard let display = network.local.interfaceDisplayName else { return name }
        return "\(display) (\(name))"
    }

    private var vpn: String {
        guard let tunnel = network.local.vpnInterface else { return String(localized: "Off") }
        return String(format: String(localized: "On (%@)"), tunnel)
    }

    // MARK: Traffic

    private var traffic: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                speed("Download", systemImage: "arrow.down.circle.fill", rate: network.downloadRate, color: .blue)
                Spacer()
                speed("Upload", systemImage: "arrow.up.circle.fill", rate: network.uploadRate, color: .orange)
            }
            chart
            HStack {
                Text("This session")
                Spacer()
                Text("↓ \(Format.bytes(network.sessionReceived))   ↑ \(Format.bytes(network.sessionSent))")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func speed(_ title: LocalizedStringKey, systemImage: String, rate: Double, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(Format.speed(rate, unit: settings.speedUnit))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var chart: some View {
        let download = String(localized: "Download")
        let upload = String(localized: "Upload")
        return Chart(network.history) { point in
            AreaMark(
                x: .value("Time", point.id),
                y: .value("Speed", point.download),
                series: .value("Direction", download)
            )
            .foregroundStyle(.blue.opacity(0.25))
            .interpolationMethod(.monotone)
            LineMark(
                x: .value("Time", point.id),
                y: .value("Speed", point.download),
                series: .value("Direction", download)
            )
            .foregroundStyle(.blue)
            .interpolationMethod(.monotone)
            LineMark(
                x: .value("Time", point.id),
                y: .value("Speed", point.upload),
                series: .value("Direction", upload)
            )
            .foregroundStyle(.orange)
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: (network.history.last?.id ?? 0) - NetworkMonitor.historyLength + 1 ... max(network.history.last?.id ?? 1, 1))
        .frame(height: 56)
        .accessibilityLabel("Network speed over the last minute")
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 10) {
            HStack {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text(updatedText(now: context.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if network.geoStatus == .loading {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        network.refreshGeo()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Refresh location")
                }
            }
            HStack {
                Toggle("Desktop widget", isOn: $settings.widgetVisible)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                Button("Settings…") {
                    dismiss()
                    actions.openSettings(.general)
                }
                .keyboardShortcut(",")
                Button("Quit") { actions.quit() }
                    .keyboardShortcut("q")
            }
        }
    }

    private func updatedText(now: Date) -> String {
        guard let date = network.geoUpdatedAt else { return String(localized: "Not updated yet") }
        if now.timeIntervalSince(date) < 60 { return String(localized: "Updated just now") }
        return String(format: String(localized: "Updated %@"), Format.relative(date, to: now))
    }
}

private extension Array where Element: Equatable {
    func removingDuplicates() -> [Element] {
        reduce(into: []) { result, element in
            if !result.contains(element) { result.append(element) }
        }
    }
}

private extension String {
    var nonEmptyOrDash: String { isEmpty ? "—" : self }
}

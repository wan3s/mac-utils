import AppKit
import SwiftUI

/// Size-dependent layout values. Compact trades detail fonts for a narrower footprint.
private struct WidgetMetrics {
    var width: CGFloat
    var padding: CGFloat
    var sectionSpacing: CGFloat
    var cornerRadius: CGFloat
    var titleFont: Font
    var valueFont: Font
    var detailFont: Font
    var barHeight: CGFloat

    static func make(_ size: WidgetSize) -> WidgetMetrics {
        switch size {
        case .compact:
            WidgetMetrics(width: 230, padding: 10, sectionSpacing: 8, cornerRadius: 12,
                          titleFont: .subheadline.weight(.semibold), valueFont: .headline,
                          detailFont: .caption2, barHeight: 5)
        case .regular:
            WidgetMetrics(width: 290, padding: 14, sectionSpacing: 12, cornerRadius: 16,
                          titleFont: .headline, valueFont: .title3.weight(.semibold),
                          detailFont: .caption, barHeight: 6)
        }
    }
}

struct DesktopWidgetView: View {
    let monitor: SystemMonitor
    @Bindable var settings: AppSettings
    let actions: AppActions

    @Environment(\.colorScheme) private var colorScheme

    private var metrics: WidgetMetrics { .make(settings.widgetSize) }

    /// With a see-through background, a soft halo keeps text legible over bright or busy wallpapers.
    private var legibilityShadow: Color {
        guard settings.widgetOpacity < 0.95 else { return .clear }
        return colorScheme == .dark ? .black.opacity(0.6) : .white.opacity(0.8)
    }

    var body: some View {
        content
            .shadow(color: legibilityShadow, radius: 1.5)
            .padding(metrics.padding)
            .frame(width: metrics.width, alignment: .leading)
            .background(
                VisualEffectBackground(opacity: settings.widgetOpacity)
            )
            .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
            .contextMenu { contextMenu }
            .fixedSize()
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            if settings.showCPU {
                CPUSection(monitor: monitor, settings: settings, metrics: metrics)
            }
            if settings.showCPU && settings.showMemory {
                Divider()
            }
            if settings.showMemory {
                MemorySection(memory: monitor.memory, settings: settings, metrics: metrics)
            }
            if settings.showDisk && (settings.showCPU || settings.showMemory) {
                Divider()
            }
            if settings.showDisk {
                DiskSection(monitor: monitor, settings: settings, metrics: metrics)
            }
            if !settings.showCPU && !settings.showMemory && !settings.showDisk {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No metrics selected").font(metrics.titleFont)
                    Text("Choose metrics in Settings › Widget.")
                        .font(metrics.detailFont)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var contextMenu: some View {
        Toggle("Lock Position", isOn: $settings.widgetLocked)
        Button("Widget Settings…") { actions.openSettings(.widget) }
        Divider()
        Button("Hide Widget") { settings.widgetVisible = false }
    }
}

// MARK: - Sections

private struct CPUSection: View {
    let monitor: SystemMonitor
    let settings: AppSettings
    let metrics: WidgetMetrics

    var body: some View {
        let cpu = monitor.cpu
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "CPU", systemImage: "cpu", value: cpu.map { Format.percent($0.total) }, metrics: metrics) {
                if settings.showCPUTemperature, let temperature = monitor.cpuTemperature {
                    TemperatureBadge(celsius: temperature, metrics: metrics)
                }
            }
            UsageBar(fraction: cpu?.total ?? 0, tint: UsageLevel.tint(cpu?.total ?? 0), height: metrics.barHeight)
                .accessibilityLabel("CPU usage")
                .accessibilityValue(Format.percent(cpu?.total ?? 0))
            if let cpu {
                DetailLine(metrics: metrics) {
                    Text(String(format: String(localized: "User %@ · System %@"),
                                Format.percent(cpu.user), Format.percent(cpu.system)))
                }
            }
            if settings.showLoadAverage, monitor.loadAverage.count == 3 {
                DetailLine(metrics: metrics) {
                    Text(String(format: String(localized: "Load average %@"),
                                monitor.loadAverage.map { Format.number($0, fractionDigits: 2) }.joined(separator: "  ")))
                }
            }
            if settings.showCPUCores, let cores = cpu?.cores, !cores.isEmpty {
                CoreGrid(cores: cores, labels: monitor.coreLabels, metrics: metrics)
                    .padding(.top, 2)
            }
        }
    }
}

private struct CoreGrid: View {
    let cores: [Double]
    let labels: [String]
    let metrics: WidgetMetrics

    var body: some View {
        let rows = stride(from: 0, to: cores.count, by: 2).map { $0 }
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            ForEach(rows, id: \.self) { start in
                GridRow {
                    cell(start)
                    if start + 1 < cores.count {
                        cell(start + 1)
                    } else {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
        .font(metrics.detailFont.monospacedDigit())
    }

    private func cell(_ index: Int) -> some View {
        let label = index < labels.count ? labels[index] : "\(index + 1)"
        let value = cores[index]
        return HStack(spacing: 5) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)
            UsageBar(fraction: value, tint: UsageLevel.tint(value), height: 4)
            Text(Format.percent(value))
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: String(localized: "Core %@"), label))
        .accessibilityValue(Format.percent(value))
    }
}

private struct MemorySection: View {
    let memory: MemoryUsage?
    let settings: AppSettings
    let metrics: WidgetMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Memory", systemImage: "memorychip", value: memory.map { Format.percent($0.fraction) }, metrics: metrics) {
                EmptyView()
            }
            UsageBar(fraction: memory?.fraction ?? 0, tint: pressureTint, height: metrics.barHeight)
                .accessibilityLabel("Memory usage")
                .accessibilityValue(Format.percent(memory?.fraction ?? 0))
            if let memory {
                DetailLine(metrics: metrics) {
                    Text(String(format: String(localized: "%@ of %@ used"),
                                Format.bytes(memory.used, style: .memory), Format.bytes(memory.total, style: .memory)))
                }
                DetailLine(metrics: metrics) {
                    Text(String(format: String(localized: "App %@ · Wired %@ · Compressed %@"),
                                Format.bytes(memory.app, style: .memory),
                                Format.bytes(memory.wired, style: .memory),
                                Format.bytes(memory.compressed, style: .memory)))
                }
                if settings.showSwap {
                    DetailLine(metrics: metrics) {
                        Text(String(format: String(localized: "Swap %@ of %@"),
                                    Format.bytes(memory.swapUsed, style: .memory), Format.bytes(memory.swapTotal, style: .memory)))
                    }
                }
                if settings.showMemoryPressure, let pressure = memory.pressure {
                    DetailLine(metrics: metrics) {
                        HStack(spacing: 4) {
                            Image(systemName: pressure.symbol)
                                .foregroundStyle(pressure.tint)
                            Text(String(format: String(localized: "Pressure: %@"), pressure.title))
                        }
                    }
                }
            }
        }
    }

    private var pressureTint: Color {
        memory?.pressure?.tint ?? UsageLevel.tint(memory?.fraction ?? 0)
    }
}

private struct DiskSection: View {
    let monitor: SystemMonitor
    let settings: AppSettings
    let metrics: WidgetMetrics

    var body: some View {
        let disk = monitor.disk
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Disk", systemImage: "internaldrive", value: disk.map { Format.percent($0.fraction) }, metrics: metrics) {
                if settings.showSSDTemperature, let temperature = monitor.ssdTemperature {
                    TemperatureBadge(celsius: temperature, metrics: metrics)
                }
            }
            UsageBar(fraction: disk?.fraction ?? 0, tint: UsageLevel.tint(disk?.fraction ?? 0, warning: 0.8, critical: 0.9),
                     height: metrics.barHeight)
                .accessibilityLabel("Disk usage")
                .accessibilityValue(Format.percent(disk?.fraction ?? 0))
            if let disk {
                DetailLine(metrics: metrics) {
                    Text(String(format: String(localized: "%@: %@ available of %@"),
                                disk.volumeName, Format.bytes(disk.available), Format.bytes(disk.total)))
                }
                if settings.showDiskActivity {
                    DetailLine(metrics: metrics) {
                        Text(String(format: String(localized: "Read %@ · Write %@"),
                                    Format.speed(disk.readRate, unit: .bytes), Format.speed(disk.writeRate, unit: .bytes)))
                    }
                }
            }
        }
    }
}

// MARK: - Building blocks

private struct SectionHeader<Accessory: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let value: String?
    let metrics: WidgetMetrics
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(metrics.titleFont)
            Spacer(minLength: 4)
            accessory()
            Text(value ?? "—")
                .font(metrics.valueFont.monospacedDigit())
        }
    }
}

private struct TemperatureBadge: View {
    let celsius: Double
    let metrics: WidgetMetrics

    var body: some View {
        Label(Format.temperature(celsius), systemImage: "thermometer.medium")
            .font(metrics.detailFont.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityLabel(String(format: String(localized: "Temperature %@"), Format.temperature(celsius)))
    }
}

private struct DetailLine<Content: View>: View {
    let metrics: WidgetMetrics
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .font(metrics.detailFont.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A slim capacity bar. Values are always shown as text next to it, so color is never the only cue.
private struct UsageBar: View {
    let fraction: Double
    let tint: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, proxy.size.width * min(max(fraction, 0), 1)))
                    .opacity(fraction > 0.005 ? 1 : 0)
            }
        }
        .frame(height: height)
        .accessibilityElement()
    }
}

private enum UsageLevel {
    static func tint(_ fraction: Double, warning: Double = 0.6, critical: Double = 0.85) -> Color {
        if fraction >= critical { return .red }
        if fraction >= warning { return .orange }
        return .green
    }
}

private extension MemoryPressure {
    var title: String {
        switch self {
        case .normal: String(localized: "Normal")
        case .warning: String(localized: "Elevated")
        case .critical: String(localized: "Critical")
        }
    }

    var symbol: String {
        switch self {
        case .normal: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}

/// Behind-window blur so the widget picks up the wallpaper. Falls back to an opaque
/// background automatically when Reduce Transparency is on.
private struct VisualEffectBackground: NSViewRepresentable {
    var opacity: Double

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.alphaValue = opacity
    }
}

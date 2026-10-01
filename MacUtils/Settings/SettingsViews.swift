import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    let loginItem: LoginItem

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                if loginItem.requiresApproval {
                    HStack {
                        Text("Allow Mac Utils in Login Items to finish turning this on.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items…") { loginItem.openSystemSettings() }
                    }
                }
                if let error = loginItem.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Picker("Network speed units", selection: $settings.speedUnit) {
                    Text("Bytes (KB/s, MB/s)").tag(SpeedUnit.bytes)
                    Text("Bits (Kbit/s, Mbit/s)").tag(SpeedUnit.bits)
                }
            } footer: {
                Text("Used in the menu bar and in the network details.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 250)
        .onAppear { loginItem.refresh() }
    }
}

struct MenuBarSettingsView: View {
    @Bindable var settings: AppSettings

    private let refreshOptions: [(minutes: Int, title: LocalizedStringKey)] = [
        (1, "Every minute"), (5, "Every 5 minutes"), (15, "Every 15 minutes"),
        (30, "Every 30 minutes"), (60, "Every hour"),
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Show country flag", isOn: $settings.showFlag)
                    .disabled(!settings.canHideFlag)
                Toggle("Show network speed", isOn: $settings.showSpeeds)
                    .disabled(!settings.canHideSpeeds)
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("At least one item stays in the menu bar.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Update location", selection: $settings.geoRefreshMinutes) {
                    ForEach(refreshOptions, id: \.minutes) { option in
                        Text(option.title).tag(option.minutes)
                    }
                }
            } header: {
                Text("Location")
            } footer: {
                Text("The country is determined from your public IP address by ipinfo.io, with ipwho.is as a fallback. The location also updates right away when your network or VPN changes.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 330)
    }
}

struct WidgetSettingsView: View {
    @Bindable var settings: AppSettings
    let monitor: SystemMonitor

    @State private var volumes: [VolumeOption] = []
    @State private var screens: [(id: UInt32, name: String)] = []

    var body: some View {
        Form {
            Section {
                Toggle("Show widget on desktop", isOn: $settings.widgetVisible)
                LabeledContent("Update interval") {
                    HStack {
                        Slider(value: $settings.widgetInterval, in: 0.5...5, step: 0.5)
                            .labelsHidden()
                            .frame(width: 180)
                        Text(Format.seconds(settings.widgetInterval))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("CPU") {
                Toggle("Show CPU", isOn: $settings.showCPU)
                Group {
                    Toggle("Usage per core", isOn: $settings.showCPUCores)
                    Toggle("Temperature", isOn: $settings.showCPUTemperature)
                        .disabled(!monitor.hasCPUTemperature)
                        .help(monitor.hasCPUTemperature ? Text(verbatim: "") : Text("This Mac doesn't report CPU temperature."))
                    Toggle("Load average", isOn: $settings.showLoadAverage)
                }
                .disabled(!settings.showCPU)
            }

            Section("Memory") {
                Toggle("Show memory", isOn: $settings.showMemory)
                Group {
                    Toggle("Swap", isOn: $settings.showSwap)
                    Toggle("Memory pressure", isOn: $settings.showMemoryPressure)
                }
                .disabled(!settings.showMemory)
            }

            Section("Disk") {
                Toggle("Show disk", isOn: $settings.showDisk)
                Group {
                    Picker("Volume", selection: $settings.diskVolumePath) {
                        ForEach(volumes) { volume in
                            Text(volume.name).tag(volume.path)
                        }
                    }
                    Toggle("Read and write speed", isOn: $settings.showDiskActivity)
                    Toggle("SSD temperature", isOn: $settings.showSSDTemperature)
                        .disabled(!monitor.hasSSDTemperature)
                }
                .disabled(!settings.showDisk)
            }

            Section {
                Picker("Size", selection: $settings.widgetSize) {
                    Text("Compact").tag(WidgetSize.compact)
                    Text("Regular").tag(WidgetSize.regular)
                }
                .pickerStyle(.segmented)
                Picker("Appearance", selection: $settings.widgetTheme) {
                    Text("System").tag(WidgetTheme.system)
                    Text("Light").tag(WidgetTheme.light)
                    Text("Dark").tag(WidgetTheme.dark)
                }
                .pickerStyle(.segmented)
                LabeledContent("Background opacity") {
                    HStack {
                        Slider(value: $settings.widgetOpacity, in: 0.2...1, step: 0.05)
                            .labelsHidden()
                            .frame(width: 180)
                        Text(Format.percent(settings.widgetOpacity))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text("A lower opacity can make text harder to read on bright wallpapers.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Position", selection: $settings.widgetPlacement) {
                    Text("Anywhere (drag to move)").tag(WidgetPlacement.free)
                    Divider()
                    Text("Top Left").tag(WidgetPlacement.topLeft)
                    Text("Top Right").tag(WidgetPlacement.topRight)
                    Text("Bottom Left").tag(WidgetPlacement.bottomLeft)
                    Text("Bottom Right").tag(WidgetPlacement.bottomRight)
                }
                Picker("Display", selection: $settings.widgetScreenID) {
                    Text("Main display").tag(UInt32(0))
                    ForEach(screens, id: \.id) { screen in
                        Text(screen.name).tag(screen.id)
                    }
                }
                Toggle("Lock position", isOn: $settings.widgetLocked)
                    .disabled(settings.widgetPlacement != .free)
                HStack {
                    Spacer()
                    Button("Reset Position") {
                        settings.widgetPlacement = .topRight
                        settings.widgetScreenID = 0
                        settings.widgetTopLeft = nil
                    }
                }
            } header: {
                Text("Position")
            } footer: {
                Text("The widget stays on the desktop, below app windows, on every Space.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 620)
        .onAppear(perform: reloadHardware)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            reloadHardware()
        }
    }

    private func reloadHardware() {
        var options = DiskSampler.volumes()
        if !options.contains(where: { $0.path == settings.diskVolumePath }) {
            options.append(VolumeOption(path: settings.diskVolumePath, name: settings.diskVolumePath))
        }
        volumes = options
        let all = NSScreen.screens
        screens = all.count > 1 ? all.map { ($0.displayID, $0.localizedName) } : []
    }
}

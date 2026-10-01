import Foundation
import IOKit

// Private IOKit HID event system API. It's the only way to read Apple Silicon die and SSD
// temperatures without root, and the reason the app can't be sandboxed.
@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: AnyObject, _ matching: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: AnyObject) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: AnyObject, _ key: CFString) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: AnyObject, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: AnyObject, _ field: Int32) -> Double

/// Reads SoC die and SSD temperatures from the HID thermal sensors.
/// Intel Macs don't expose these sensors, so both readings are `nil` there.
final class TemperatureSensors {
    private static let temperatureEventType: Int64 = 15 // kIOHIDEventTypeTemperature
    private static let temperatureField = Int32(15 << 16)

    private var cpuSensors: [AnyObject] = []
    private var ssdSensors: [AnyObject] = []
    // Services are only valid while their client is alive.
    private var client: AnyObject?

    init() {
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else { return }
        self.client = client
        // Vendor page 0xff00, usage 5: temperature sensors.
        let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        _ = IOHIDEventSystemClientSetMatching(client, matching)
        guard let services = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [AnyObject] else {
            return
        }
        for service in services {
            let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String ?? ""
            if name.hasPrefix("PMU") && name.contains("tdie") {
                cpuSensors.append(service)
            } else if name.contains("NAND") {
                ssdSensors.append(service)
            }
        }
    }

    var hasCPUSensors: Bool { !cpuSensors.isEmpty }
    var hasSSDSensors: Bool { !ssdSensors.isEmpty }

    /// Average SoC die temperature in °C.
    func cpuTemperature() -> Double? { average(cpuSensors) }

    /// SSD (NAND) temperature in °C.
    func ssdTemperature() -> Double? { average(ssdSensors) }

    private func average(_ sensors: [AnyObject]) -> Double? {
        let values = sensors.compactMap { sensor -> Double? in
            guard let event = IOHIDServiceClientCopyEvent(sensor, Self.temperatureEventType, 0, 0)?.takeRetainedValue()
            else { return nil }
            let value = IOHIDEventGetFloatValue(event, Self.temperatureField)
            return (1..<130).contains(value) ? value : nil
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

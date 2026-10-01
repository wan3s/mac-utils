import Foundation

enum SpeedUnit: String, CaseIterable, Identifiable {
    case bytes
    case bits

    var id: String { rawValue }
}

/// Locale-aware formatting shared by the menu bar, the popover and the widget.
enum Format {
    private static let byteSpeedUnits = [
        String(localized: "KB/s"), String(localized: "MB/s"), String(localized: "GB/s"),
    ]
    private static let bitSpeedUnits = [
        String(localized: "Kbit/s"), String(localized: "Mbit/s"), String(localized: "Gbit/s"),
    ]

    private static let numberFormatters: [NumberFormatter] = (0...2).map { digits in
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter
    }

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let temperatureFormatter: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        // `.short` drops the scale letter ("104°"), which is ambiguous; `.medium` keeps it ("104°F").
        formatter.unitStyle = .medium
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let secondsFormatter: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.unitStyle = .short
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.minimumFractionDigits = 1
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter
    }()

    /// Unit labels used by `speed(_:unit:)`, smallest first.
    static func speedUnits(_ unit: SpeedUnit) -> [String] {
        unit == .bits ? bitSpeedUnits : byteSpeedUnits
    }

    /// Decimal (SI) rate starting at kilo, e.g. "0.4 KB/s", "12 MB/s", "1.2 Mbit/s".
    static func speed(_ bytesPerSecond: Double, unit: SpeedUnit) -> String {
        let units = speedUnits(unit)
        var value = max(0, bytesPerSecond) * (unit == .bits ? 8 : 1) / 1000
        var index = 0
        while value >= 999.5, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        return "\(number(value, fractionDigits: value < 9.95 ? 1 : 0)) \(units[index])"
    }

    static func number(_ value: Double, fractionDigits: Int) -> String {
        let formatter = numberFormatters[min(max(fractionDigits, 0), numberFormatters.count - 1)]
        return formatter.string(from: value as NSNumber) ?? "\(value)"
    }

    static func percent(_ fraction: Double) -> String {
        percentFormatter.string(from: min(max(fraction, 0), 1) as NSNumber) ?? ""
    }

    /// Storage sizes use decimal units like Finder; memory uses binary units like Activity Monitor.
    static func bytes(_ count: UInt64, style: ByteCountFormatter.CountStyle = .file) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: count), countStyle: style)
    }

    static func temperature(_ celsius: Double) -> String {
        temperatureFormatter.string(from: Measurement(value: celsius, unit: UnitTemperature.celsius))
    }

    static func seconds(_ value: Double) -> String {
        secondsFormatter.string(from: Measurement(value: value, unit: UnitDuration.seconds))
    }

    /// Formatter for relative dates in the app's own UI language.
    static func relative(_ date: Date, to now: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = appLocale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// The locale of the localization the app is actually running in (en or ru).
    static var appLocale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }
}

enum CountryFlag {
    /// Builds a flag emoji from an ISO 3166-1 alpha-2 code using regional indicator symbols.
    static func emoji(for countryCode: String) -> String? {
        let code = countryCode.uppercased()
        guard code.count == 2, code.unicodeScalars.allSatisfy({ (65...90).contains($0.value) }) else {
            return nil
        }
        var scalars = String.UnicodeScalarView()
        for scalar in code.unicodeScalars {
            guard let indicator = UnicodeScalar(0x1F1E6 + scalar.value - 65) else { return nil }
            scalars.append(indicator)
        }
        return String(scalars)
    }

    static func localizedName(for countryCode: String) -> String? {
        Format.appLocale.localizedString(forRegionCode: countryCode)
    }
}

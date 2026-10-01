import Foundation

struct GeoInfo: Equatable {
    var ip: String
    var countryCode: String
    var region: String?
    var city: String?
    var timeZone: String?
    var provider: String?
    var asn: String?

    var flag: String? { CountryFlag.emoji(for: countryCode) }
    var countryName: String { CountryFlag.localizedName(for: countryCode) ?? countryCode }
}

enum GeoIPError: Error {
    case invalidResponse
}

/// Looks up the public IP address and its location. ipinfo.io is tried first, ipwho.is is the fallback.
struct GeoIPService {
    func lookup() async throws -> GeoInfo {
        do {
            return try await ipInfo()
        } catch {
            try Task.checkCancellation()
            return try await ipWhoIs()
        }
    }

    private func ipInfo() async throws -> GeoInfo {
        let json = try await fetchJSON("https://ipinfo.io/json")
        guard let ip = json["ip"] as? String, let country = json["country"] as? String else {
            throw GeoIPError.invalidResponse
        }
        // "org" looks like "AS13335 Cloudflare, Inc.".
        var asn: String?
        var provider = json["org"] as? String
        if let org = provider, org.hasPrefix("AS"), let space = org.firstIndex(of: " ") {
            asn = String(org[..<space])
            provider = String(org[org.index(after: space)...])
        }
        return GeoInfo(
            ip: ip,
            countryCode: country,
            region: (json["region"] as? String).nonEmpty,
            city: (json["city"] as? String).nonEmpty,
            timeZone: (json["timezone"] as? String).nonEmpty,
            provider: provider.nonEmpty,
            asn: asn
        )
    }

    private func ipWhoIs() async throws -> GeoInfo {
        let json = try await fetchJSON("https://ipwho.is/")
        guard json["success"] as? Bool == true,
              let ip = json["ip"] as? String,
              let country = json["country_code"] as? String
        else { throw GeoIPError.invalidResponse }
        let connection = json["connection"] as? [String: Any]
        let timeZone = json["timezone"] as? [String: Any]
        return GeoInfo(
            ip: ip,
            countryCode: country,
            region: (json["region"] as? String).nonEmpty,
            city: (json["city"] as? String).nonEmpty,
            timeZone: (timeZone?["id"] as? String).nonEmpty,
            provider: ((connection?["isp"] as? String).nonEmpty ?? (connection?["org"] as? String)).nonEmpty,
            asn: (connection?["asn"] as? Int).map { "AS\($0)" }
        )
    }

    private func fetchJSON(_ address: String) async throws -> [String: Any] {
        // A fresh ephemeral session per lookup: a pooled connection opened before a VPN switch
        // would still report the old exit IP.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: URL(string: address)!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw GeoIPError.invalidResponse }
        return json
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value
    }
}

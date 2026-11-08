import Foundation

public struct NearbyBuckets: Equatable, Sendable {
    public var ev: [POI]
    public var fuel: [POI]
    public var wc: [POI]
    public var parking: [POI]

    public init(ev: [POI] = [], fuel: [POI] = [], wc: [POI] = [], parking: [POI] = []) {
        self.ev = ev
        self.fuel = fuel
        self.wc = wc
        self.parking = parking
    }
}

func jsonObject(_ data: Data) throws -> Any {
    try JSONSerialization.jsonObject(with: data)
}

func asDouble(_ value: Any?) -> Double? {
    if value == nil || value is NSNull { return nil }
    if let number = value as? NSNumber { return number.doubleValue }
    if let text = value as? String { return Double(text) }
    return nil
}

func asString(_ value: Any?) -> String? {
    if let text = value as? String { return text }
    return nil
}

func asDict(_ value: Any?) -> [String: Any]? { value as? [String: Any] }

func asArray(_ value: Any?) -> [Any]? { value as? [Any] }

private func tagString(_ value: Any?) -> String? {
    if let text = value as? String { return text }
    if let number = value as? NSNumber { return number.stringValue }
    return nil
}

private func top(_ items: [POI]) -> [POI] {
    Array(items.filter { $0.lat.isFinite && $0.lon.isFinite }.sorted { $0.mi < $1.mi }.prefix(3))
}

private func shapeOSM(_ element: [String: Any], originLat: Double, originLon: Double) -> (String, POI)? {
    let tags = asDict(element["tags"]) ?? [:]
    guard let amenity = tagString(tags["amenity"]) else { return nil }
    let kind: String
    switch amenity {
    case "charging_station": kind = "ev"
    case "fuel": kind = "fuel"
    case "toilets": kind = "wc"
    case "parking": kind = "parking"
    default: return nil
    }
    let center = asDict(element["center"])
    guard let lat = asDouble(element["lat"]) ?? center.flatMap({ asDouble($0["lat"]) }),
          let lon = asDouble(element["lon"]) ?? center.flatMap({ asDouble($0["lon"]) }) else { return nil }
    let named = tagString(tags["name"]) ?? tagString(tags["brand"]) ?? tagString(tags["operator"])
    let fallback = ["ev": "EV charger", "fuel": "Gas station", "wc": "Restroom", "parking": "Parking"][kind] ?? "Place"
    let name = named ?? "\(fallback) (unnamed)"
    var facts: [String] = []
    if let hours = tagString(tags["opening_hours"]) { facts.append("Hours: \(hours)") }
    if kind == "wc" {
        if let access = tagString(tags["access"]) { facts.append("Access: \(access)") }
        if let fee = tagString(tags["fee"]) { facts.append("Fee: \(fee)") }
        if let wheelchair = tagString(tags["wheelchair"]) { facts.append("Wheelchair: \(wheelchair)") }
    }
    if kind == "ev" {
        let sockets = tags.keys.filter { key in
            guard key.hasPrefix("socket:") else { return false }
            let rest = key.dropFirst("socket:".count)
            return !rest.contains(":")
        }.map { String($0.dropFirst("socket:".count)) }.sorted()
        if !sockets.isEmpty { facts.append("Plugs: \(sockets.joined(separator: ", "))") }
        if let fee = tagString(tags["fee"]) { facts.append("Fee: \(fee)") }
    }
    if kind == "parking" {
        for key in ["fee", "access", "maxstay", "parking", "capacity", "supervised"] {
            if let value = tagString(tags[key]), !value.isEmpty { facts.append("\(key): \(value)") }
        }
    }
    let address = [tagString(tags["addr:housenumber"]), tagString(tags["addr:street"]), tagString(tags["addr:city"])]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    let poi = POI(name: name, lat: lat, lon: lon, addr: address, facts: facts, mi: miles(lat1: originLat, lon1: originLon, lat2: lat, lon2: lon), src: SourceName.osm)
    return (kind, poi)
}

public func parseOverpass(_ data: Data, originLat: Double, originLon: Double) throws -> NearbyBuckets {
    guard let root = try jsonObject(data) as? [String: Any] else { throw FetchFailure.badStatus }
    guard let elements = root["elements"] as? [Any] else { throw FetchFailure.badStatus }
    var buckets = NearbyBuckets()
    for element in elements {
        guard let dict = asDict(element), let (kind, poi) = shapeOSM(dict, originLat: originLat, originLon: originLon) else { continue }
        switch kind {
        case "ev": buckets.ev.append(poi)
        case "fuel": buckets.fuel.append(poi)
        case "wc": buckets.wc.append(poi)
        case "parking": buckets.parking.append(poi)
        default: break
        }
    }
    buckets.ev = top(buckets.ev)
    buckets.fuel = top(buckets.fuel)
    buckets.wc = top(buckets.wc)
    buckets.parking = top(buckets.parking)
    return buckets
}

public func parseNREL(_ data: Data, originLat: Double, originLon: Double) throws -> [POI] {
    guard let root = try jsonObject(data) as? [String: Any] else { throw FetchFailure.badStatus }
    let stations = asArray(root["fuel_stations"]) ?? []
    return stations.compactMap { item -> POI? in
        guard let station = asDict(item),
              let lat = asDouble(station["latitude"]),
              let lon = asDouble(station["longitude"]) else { return nil }
        var facts: [String] = []
        if let hours = asString(station["access_days_time"]), !hours.isEmpty { facts.append("Hours: \(hours)") }
        if let plugs = asArray(station["ev_connector_types"])?.compactMap(asString), !plugs.isEmpty {
            facts.append("Plugs: \(plugs.joined(separator: ", "))")
        }
        var levels: [String] = []
        if let fast = asDouble(station["ev_dc_fast_num"]), fast > 0 { levels.append("\(Int(fast)) DC fast") }
        if let level2 = asDouble(station["ev_level2_evse_num"]), level2 > 0 { levels.append("\(Int(level2)) Level 2") }
        if !levels.isEmpty { facts.append(levels.joined(separator: ", ")) }
        if let price = asString(station["ev_pricing"]), !price.isEmpty { facts.append("Price: \(price)") }
        if let network = asString(station["ev_network"]), !network.isEmpty { facts.append("Network: \(network)") }
        let address = [asString(station["street_address"]), asString(station["city"])].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        let distance = asDouble(station["distance"]) ?? miles(lat1: originLat, lon1: originLon, lat2: lat, lon2: lon)
        return POI(name: asString(station["station_name"]) ?? "EV charger", lat: lat, lon: lon, addr: address, facts: facts, mi: distance, src: SourceName.doe)
    }
}

public func parseNominatimSearch(_ data: Data, originLat: Double, originLon: Double, kind: String) throws -> [POI] {
    guard let rows = try jsonObject(data) as? [Any] else { throw FetchFailure.badStatus }
    let fallback = ["ev": "EV charger", "fuel": "Gas station", "wc": "Restroom"][kind] ?? "Place"
    let places = rows.compactMap { item -> POI? in
        guard let row = asDict(item), let lat = asDouble(row["lat"]), let lon = asDouble(row["lon"]) else { return nil }
        let display = asString(row["display_name"]) ?? ""
        let address = display.split(separator: ",", omittingEmptySubsequences: false).prefix(3).joined(separator: ",")
        return POI(
            name: asString(row["name"]) ?? fallback,
            lat: lat,
            lon: lon,
            addr: address,
            facts: [],
            mi: miles(lat1: originLat, lon1: originLon, lat2: lat, lon2: lon),
            src: SourceName.nominatim
        )
    }
    return top(places)
}

public func parseNominatimReverse(_ data: Data) throws -> Place {
    guard let root = try jsonObject(data) as? [String: Any] else { throw FetchFailure.badStatus }
    let address = asDict(root["address"]) ?? [:]
    func first(_ keys: [String]) -> String? {
        for key in keys {
            if let value = asString(address[key]), !value.isEmpty { return value }
        }
        return nil
    }
    let parts = [
        first(["road", "neighbourhood", "suburb", "hamlet"]),
        first(["city", "town", "village", "county"]),
        first(["state"])
    ].compactMap { $0 }
    let full = asString(root["display_name"])
    let short = parts.isEmpty ? (full ?? "") : parts.joined(separator: ", ")
    return Place(short: short, full: full)
}

public func parseWeather(_ data: Data, now: Date) throws -> WeatherSnapshot {
    guard let root = try jsonObject(data) as? [String: Any] else { throw FetchFailure.badStatus }
    let current = asDict(root["current"]) ?? [:]
    let daily = asDict(root["daily"]) ?? [:]
    let rain = asArray(daily["precipitation_probability_max"])?.first
    let uv = asArray(daily["uv_index_max"])?.first
    return WeatherSnapshot(
        t: asDouble(current["temperature_2m"]),
        feels: asDouble(current["apparent_temperature"]),
        code: asDouble(current["weather_code"]).map { Int($0) },
        wind: asDouble(current["wind_speed_10m"]),
        gust: asDouble(current["wind_gusts_10m"]),
        precip: asDouble(current["precipitation"]),
        vis: asDouble(current["visibility"]),
        rainChance: asDouble(rain),
        uv: asDouble(uv),
        at: now.timeIntervalSince1970 * 1000
    )
}

public func mergeEV(_ primary: [POI], _ extra: [POI]) -> [POI] {
    let added = extra.filter { candidate in
        !primary.contains { miles(lat1: $0.lat, lon1: $0.lon, lat2: candidate.lat, lon2: candidate.lon) < 0.05 }
    }
    return top(primary + added)
}

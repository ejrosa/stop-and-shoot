import Foundation

public enum ServiceEndpoints {
    public static let overpassMirrors = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
        "https://overpass.private.coffee/api/interpreter"
    ]
    public static let nrelNearest = "https://developer.nlr.gov/api/alt-fuel-stations/v1/nearest.json"
    /// Public demo key already shipped in the website. Not a secret. Replace before a store release.
    public static let nrelDemoAPIKey = "DEMO_KEY"
    public static let nominatimReverse = "https://nominatim.openstreetmap.org/reverse"
    public static let nominatimSearch = "https://nominatim.openstreetmap.org/search"
    public static let openMeteoForecast = "https://api.open-meteo.com/v1/forecast"
    public static let appleMaps = "https://maps.apple.com/"

    public static var allLookupURLs: [String] {
        overpassMirrors + [nrelNearest, nominatimReverse, nominatimSearch, openMeteoForecast]
    }
}

public enum SourceName {
    public static let doe = "U.S. DOE AFDC"
    public static let overpass = "OpenStreetMap (Overpass)"
    public static let nominatim = "OpenStreetMap (Nominatim)"
    public static let osm = "OpenStreetMap"
}

public enum LookupErrorText {
    public static let doe = "DOE EV list"
    public static let overpass = "OpenStreetMap Overpass (parking lots, full hours)"
}

public struct HTTPRequest: Equatable, Sendable {
    public enum Method: String, Sendable { case GET, POST }
    public var method: Method
    public var url: URL
    public var body: String?
    public var headers: [String: String]
    public var timeout: TimeInterval

    public init(method: Method, url: URL, body: String?, headers: [String: String], timeout: TimeInterval) {
        self.method = method
        self.url = url
        self.body = body
        self.headers = headers
        self.timeout = timeout
    }
}

public protocol HTTPFetching {
    func send(_ request: HTTPRequest) async throws -> Data
}

public enum FetchFailure: Error, Equatable {
    case badStatus
}

/// Matches JavaScript encodeURIComponent so Overpass queries are escaped the same way as the website.
public func jsEncodeURIComponent(_ value: String) -> String {
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
    var out = ""
    for scalar in value.unicodeScalars {
        if allowed.contains(scalar) {
            out.unicodeScalars.append(scalar)
        } else {
            let utf8 = String(scalar).data(using: .utf8) ?? Data()
            for byte in utf8 {
                out += String(format: "%%%02X", byte)
            }
        }
    }
    return out
}

public func formatCoord(_ value: Double) -> String {
    guard value.isFinite else { return "0" }
    let negative = value < 0
    let scaled = (abs(value) * 1_000_000).rounded(.toNearestOrAwayFromZero)
    if scaled < 1 { return "0" }
    let units = Int64(scaled.rounded(.toNearestOrAwayFromZero))
    var digits = String(units)
    if digits.count <= 6 {
        digits = String(repeating: "0", count: 7 - digits.count) + digits
    }
    let fracStart = digits.index(digits.endIndex, offsetBy: -6)
    let whole = String(digits[..<fracStart])
    var frac = String(digits[fracStart...])
    while frac.last == "0" { frac.removeLast() }
    let number = frac.isEmpty ? whole : "\(whole).\(frac)"
    return negative ? "-\(number)" : number
}

public func roundCoordinate(_ value: Double) -> Double {
    Double(formatCoord(value)) ?? value
}

public func roundAccuracy(_ meters: Double) -> Double {
    meters.rounded(.toNearestOrAwayFromZero)
}

public func miles(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let radius = 3958.8
    let r = Double.pi / 180
    let dLa = (lat2 - lat1) * r
    let dLo = (lon2 - lon1) * r
    let a = pow(sin(dLa / 2), 2) + cos(lat1 * r) * cos(lat2 * r) * pow(sin(dLo / 2), 2)
    return 2 * radius * asin(min(1, sqrt(a)))
}

public func overpassQuery(lat: Double, lon: Double) -> String {
    let la = formatCoord(lat)
    let lo = formatCoord(lon)
    return "[out:json][timeout:25];(\n"
        + "nwr[\"amenity\"=\"charging_station\"](around:16000,\(la),\(lo));\n"
        + "nwr[\"amenity\"=\"fuel\"](around:10000,\(la),\(lo));\n"
        + "nwr[\"amenity\"=\"toilets\"](around:8000,\(la),\(lo));\n"
        + "nwr[\"amenity\"=\"parking\"](around:800,\(la),\(lo));\n"
        + ");out center tags;"
}

private func lookupHeaders() -> [String: String] {
    [
        "User-Agent": AppIdentity.userAgent,
        "Accept": "application/json"
    ]
}

public func overpassRequest(mirror: String, lat: Double, lon: Double) -> HTTPRequest? {
    guard let url = URL(string: mirror) else { return nil }
    var headers = lookupHeaders()
    headers["Content-Type"] = "application/x-www-form-urlencoded"
    return HTTPRequest(
        method: .POST,
        url: url,
        body: "data=" + jsEncodeURIComponent(overpassQuery(lat: lat, lon: lon)),
        headers: headers,
        timeout: 12
    )
}

public func nrelRequest(lat: Double, lon: Double, apiKey: String) -> HTTPRequest? {
    var components = URLComponents(string: ServiceEndpoints.nrelNearest)
    components?.queryItems = [
        URLQueryItem(name: "api_key", value: apiKey),
        URLQueryItem(name: "latitude", value: formatCoord(lat)),
        URLQueryItem(name: "longitude", value: formatCoord(lon)),
        URLQueryItem(name: "radius", value: "15"),
        URLQueryItem(name: "fuel_type", value: "ELEC"),
        URLQueryItem(name: "status", value: "E"),
        URLQueryItem(name: "limit", value: "3")
    ]
    guard let url = components?.url else { return nil }
    return HTTPRequest(method: .GET, url: url, body: nil, headers: lookupHeaders(), timeout: 12)
}

public func nominatimReverseRequest(lat: Double, lon: Double) -> HTTPRequest? {
    var components = URLComponents(string: ServiceEndpoints.nominatimReverse)
    components?.queryItems = [
        URLQueryItem(name: "format", value: "jsonv2"),
        URLQueryItem(name: "lat", value: formatCoord(lat)),
        URLQueryItem(name: "lon", value: formatCoord(lon)),
        URLQueryItem(name: "zoom", value: "16"),
        URLQueryItem(name: "addressdetails", value: "1")
    ]
    guard let url = components?.url else { return nil }
    return HTTPRequest(method: .GET, url: url, body: nil, headers: lookupHeaders(), timeout: 12)
}

public func nominatimViewbox(lat: Double, lon: Double, delta: Double) -> String {
    [lon - delta, lat + delta, lon + delta, lat - delta].map { formatFixed($0) }.joined(separator: ",")
}

private func formatFixed(_ value: Double) -> String {
    String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
}

public func nominatimSearchRequest(lat: Double, lon: Double, amenity: String, delta: Double) -> HTTPRequest? {
    var components = URLComponents(string: ServiceEndpoints.nominatimSearch)
    components?.queryItems = [
        URLQueryItem(name: "format", value: "jsonv2"),
        URLQueryItem(name: "amenity", value: amenity),
        URLQueryItem(name: "viewbox", value: nominatimViewbox(lat: lat, lon: lon, delta: delta)),
        URLQueryItem(name: "bounded", value: "1"),
        URLQueryItem(name: "limit", value: "40"),
        URLQueryItem(name: "addressdetails", value: "0")
    ]
    guard let url = components?.url else { return nil }
    return HTTPRequest(method: .GET, url: url, body: nil, headers: lookupHeaders(), timeout: 12)
}

public func openMeteoRequest(lat: Double, lon: Double) -> HTTPRequest? {
    var components = URLComponents(string: ServiceEndpoints.openMeteoForecast)
    components?.queryItems = [
        URLQueryItem(name: "latitude", value: formatCoord(lat)),
        URLQueryItem(name: "longitude", value: formatCoord(lon)),
        URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m,wind_gusts_10m,precipitation,visibility,is_day"),
        URLQueryItem(name: "daily", value: "precipitation_probability_max,uv_index_max"),
        URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
        URLQueryItem(name: "wind_speed_unit", value: "mph"),
        URLQueryItem(name: "precipitation_unit", value: "inch"),
        URLQueryItem(name: "timezone", value: "auto"),
        URLQueryItem(name: "forecast_days", value: "1")
    ]
    guard let url = components?.url else { return nil }
    return HTTPRequest(method: .GET, url: url, body: nil, headers: lookupHeaders(), timeout: 12)
}

public func appleMapsDirections(lat: Double, lon: Double, label: String) -> URL? {
    var components = URLComponents(string: ServiceEndpoints.appleMaps)
    components?.queryItems = [
        URLQueryItem(name: "daddr", value: "\(formatCoord(lat)),\(formatCoord(lon))"),
        URLQueryItem(name: "q", value: label.isEmpty ? "Spot" : label)
    ]
    return components?.url
}

public func appleMapsView(lat: Double, lon: Double, label: String) -> URL? {
    var components = URLComponents(string: ServiceEndpoints.appleMaps)
    components?.queryItems = [
        URLQueryItem(name: "ll", value: "\(formatCoord(lat)),\(formatCoord(lon))"),
        URLQueryItem(name: "q", value: label.isEmpty ? "Spot" : label)
    ]
    return components?.url
}

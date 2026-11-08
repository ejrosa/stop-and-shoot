import Foundation

public struct LocationFix: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var horizontalAccuracy: Double
    public var timestamp: Date

    public init(latitude: Double, longitude: Double, horizontalAccuracy: Double, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }
}

public enum MarkFailure: Error, Equatable, Sendable {
    case permissionDenied
    case servicesOff
    case timedOut
    case invalidFix
}

public enum Speech {
    public static let busy = "Already saving a spot."
    public static let storageFailed = "Couldn't save the spot. The phone couldn't write the spot list."

    public static func saved(pin: Pin, locale: Locale, timeZone: TimeZone) -> String {
        let time = shortTime(Date(timeIntervalSince1970: pin.ts / 1000), locale: locale, timeZone: timeZone)
        guard let acc = pin.acc else { return "Spot saved at \(time)." }
        let meters = Int(acc.rounded(.toNearestOrAwayFromZero))
        if acc > 100 {
            return "Spot saved at \(time), accuracy about \(meters) meters. Check the map when you are parked."
        }
        return "Spot saved at \(time), accuracy \(meters) meters."
    }

    public static func failed(_ failure: MarkFailure) -> String {
        switch failure {
        case .permissionDenied:
            return "Couldn't save the spot. Location permission is off."
        case .servicesOff:
            return "Couldn't save the spot. Location services are off."
        case .timedOut:
            return "Couldn't save the spot. No GPS fix."
        case .invalidFix:
            return "Couldn't save the spot. The GPS fix was invalid."
        }
    }
}

public func shortTime(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.dateFormat = "h:mm a"
    formatter.amSymbol = "AM"
    formatter.pmSymbol = "PM"
    return formatter.string(from: date)
}

public func sanitizeNote(_ note: String?) -> String {
    guard var note else { return "" }
    note = note.replacingOccurrences(of: "\0", with: "")
    if note.count > 4000 {
        note = String(note.prefix(4000))
    }
    return note
}

public func sanitizeNewTags(_ tags: [String]) -> [String] {
    var out: [String] = []
    for tag in tags {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\0", with: "")
        if trimmed.isEmpty { continue }
        let capped = String(trimmed.prefix(40))
        if !out.contains(capped) { out.append(capped) }
        if out.count == 12 { break }
    }
    return out
}

public func makePin(id: String, fix: LocationFix, note: String?, tags: [String], now: Date) -> Result<Pin, MarkFailure> {
    guard fix.horizontalAccuracy >= 0,
          fix.latitude.isFinite, fix.longitude.isFinite,
          (-90...90).contains(fix.latitude),
          (-180...180).contains(fix.longitude) else {
        return .failure(.invalidFix)
    }
    let pin = Pin(
        id: id,
        ts: now.timeIntervalSince1970 * 1000,
        lat: roundCoordinate(fix.latitude),
        lon: roundCoordinate(fix.longitude),
        acc: roundAccuracy(fix.horizontalAccuracy),
        fixTs: fix.timestamp.timeIntervalSince1970 * 1000,
        name: "",
        tags: sanitizeNewTags(tags),
        note: sanitizeNote(note),
        parking: ""
    )
    return .success(pin)
}

public struct MarkLink: Equatable, Sendable {
    public var note: String?
    public var tags: [String]
}

/// Reads a mark link. Coordinates in the URL are ignored so another app cannot write a fake pin.
public func parseMarkLink(_ url: URL) -> MarkLink? {
    guard url.scheme?.lowercased() == "stopandshoot" else { return nil }
    let host = url.host?.lowercased()
    let path = url.path.lowercased()
    guard host == "mark" || path == "/mark" || path == "mark" else { return nil }
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let note = items.first { $0.name == "note" }?.value
    let tag = items.first { $0.name == "tag" }?.value
    let tags = tag.map { [$0] } ?? []
    return MarkLink(note: note, tags: tags)
}

public actor MarkGate {
    private var busy = false

    public init() {}

    /// Runs `body` when idle. A second call while the first is still running returns nil.
    public func run<T: Sendable>(_ body: @Sendable () async -> T) async -> T? {
        if busy { return nil }
        busy = true
        defer { busy = false }
        return await body()
    }
}

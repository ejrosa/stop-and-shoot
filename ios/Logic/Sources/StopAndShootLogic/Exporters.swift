import Foundation

public func iso8601Millis(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
}

public func exportFileName(extension ext: String, now: Date) -> String {
    let day = String(iso8601Millis(now).prefix(10))
    return "spots-\(day).\(ext)"
}

public func xmlEscape(_ value: String) -> String {
    var out = ""
    for character in value {
        switch character {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        case "\"": out += "&quot;"
        case "'": out += "&#39;"
        default: out.append(character)
        }
    }
    return out
}

private func csvQuote(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

private func sortedForExport(_ pins: [Pin]) -> [Pin] {
    pins.sorted { lhs, rhs in
        if lhs.ts == rhs.ts { return lhs.id < rhs.id }
        return lhs.ts < rhs.ts
    }
}

public func exportJSON(pins: [Pin], appName: String, exportedAt: Date) throws -> Data {
    struct Envelope: Encodable {
        var app: String
        var exported: String
        var pins: [Pin]
    }
    let envelope = Envelope(app: appName, exported: iso8601Millis(exportedAt), pins: sortedForExport(pins))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(envelope)
}

public func exportCSV(pins: [Pin]) -> String {
    let rows = sortedForExport(pins).map { pin -> String in
        let time = iso8601Millis(Date(timeIntervalSince1970: pin.ts / 1000))
        let accuracy = pin.acc.map { String(Int($0.rounded(.toNearestOrAwayFromZero))) } ?? ""
        let fields = [time, formatCoord(pin.lat), formatCoord(pin.lon), accuracy, pin.name, pin.tags.joined(separator: "; "), pin.note, pin.parking]
        return fields.map(csvQuote).joined(separator: ",")
    }
    return (["time_iso,lat,lon,accuracy_m,name,tags,note,parking_cautions"] + rows).joined(separator: "\n")
}

public func exportGPX(pins: [Pin], appName: String) -> String {
    let points = sortedForExport(pins).map { pin -> String in
        let time = iso8601Millis(Date(timeIntervalSince1970: pin.ts / 1000))
        let parts = [pin.tags.joined(separator: ", "), pin.note, pin.parking.isEmpty ? "" : "Parking: " + pin.parking].filter { !$0.isEmpty }
        let name = pin.name.isEmpty ? "Spot" : pin.name
        return "<wpt lat=\"\(formatCoord(pin.lat))\" lon=\"\(formatCoord(pin.lon))\"><time>\(time)</time><name>\(xmlEscape(name))</name><desc>\(xmlEscape(parts.joined(separator: " | ")))</desc></wpt>"
    }
    return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        + "<gpx version=\"1.1\" creator=\"\(xmlEscape(appName))\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n"
        + points.joined(separator: "\n")
        + "\n</gpx>"
}

public func shareText(pin: Pin) -> String {
    var lines = ["\(pin.name.isEmpty ? "Spot" : pin.name) (\(formatCoord(pin.lat)), \(formatCoord(pin.lon)))"]
    if !pin.note.isEmpty { lines.append(pin.note) }
    if let url = appleMapsView(lat: pin.lat, lon: pin.lon, label: pin.name) {
        lines.append(url.absoluteString)
    }
    return lines.joined(separator: "\n")
}

public func coordinateLine(pin: Pin) -> String {
    "\(formatCoord(pin.lat)), \(formatCoord(pin.lon))"
}

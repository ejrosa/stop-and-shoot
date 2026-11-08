import Foundation

public struct POI: Codable, Equatable, Sendable {
    public var name: String
    public var lat: Double
    public var lon: Double
    public var addr: String
    public var facts: [String]
    public var mi: Double
    public var src: String

    public init(name: String, lat: Double, lon: Double, addr: String, facts: [String], mi: Double, src: String) {
        self.name = name
        self.lat = lat
        self.lon = lon
        self.addr = addr
        self.facts = facts
        self.mi = mi
        self.src = src
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        guard let lat = try? c.decode(Double.self, forKey: .lat), let lon = try? c.decode(Double.self, forKey: .lon) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "POI needs coordinates"))
        }
        self.lat = lat
        self.lon = lon
        addr = (try? c.decode(String.self, forKey: .addr)) ?? ""
        facts = (try? c.decode([String].self, forKey: .facts)) ?? []
        mi = (try? c.decode(Double.self, forKey: .mi)) ?? 0
        src = (try? c.decode(String.self, forKey: .src)) ?? ""
    }
}

public struct NearbySnapshot: Codable, Equatable, Sendable {
    public var ev: [POI]
    public var fuel: [POI]
    public var wc: [POI]
    public var parking: [POI]
    public var status: String
    public var errors: [String]
    public var sources: [String]
    public var at: Double?

    public init(ev: [POI] = [], fuel: [POI] = [], wc: [POI] = [], parking: [POI] = [], status: String, errors: [String] = [], sources: [String] = [], at: Double? = nil) {
        self.ev = ev
        self.fuel = fuel
        self.wc = wc
        self.parking = parking
        self.status = status
        self.errors = errors
        self.sources = sources
        self.at = at
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ev = (try? c.decode([POI].self, forKey: .ev)) ?? []
        fuel = (try? c.decode([POI].self, forKey: .fuel)) ?? []
        wc = (try? c.decode([POI].self, forKey: .wc)) ?? []
        parking = (try? c.decode([POI].self, forKey: .parking)) ?? []
        status = (try? c.decode(String.self, forKey: .status)) ?? "ok"
        errors = (try? c.decode([String].self, forKey: .errors)) ?? []
        sources = (try? c.decode([String].self, forKey: .sources)) ?? []
        at = try? c.decodeIfPresent(Double.self, forKey: .at) ?? nil
    }
}

public struct WeatherSnapshot: Codable, Equatable, Sendable {
    public var t: Double?
    public var feels: Double?
    public var code: Int?
    public var wind: Double?
    public var gust: Double?
    public var precip: Double?
    public var vis: Double?
    public var rainChance: Double?
    public var uv: Double?
    public var at: Double

    public init(t: Double? = nil, feels: Double? = nil, code: Int? = nil, wind: Double? = nil, gust: Double? = nil, precip: Double? = nil, vis: Double? = nil, rainChance: Double? = nil, uv: Double? = nil, at: Double) {
        self.t = t
        self.feels = feels
        self.code = code
        self.wind = wind
        self.gust = gust
        self.precip = precip
        self.vis = vis
        self.rainChance = rainChance
        self.uv = uv
        self.at = at
    }
}

public struct Place: Codable, Equatable, Sendable {
    public var short: String
    public var full: String?

    public init(short: String, full: String?) {
        self.short = short
        self.full = full
    }
}

public struct Pin: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var ts: Double
    public var lat: Double
    public var lon: Double
    public var acc: Double?
    public var fixTs: Double?
    public var name: String
    public var tags: [String]
    public var note: String
    public var parking: String
    public var nearby: NearbySnapshot?
    public var weather: WeatherSnapshot?
    public var place: Place?

    public init(id: String, ts: Double, lat: Double, lon: Double, acc: Double? = nil, fixTs: Double? = nil, name: String = "", tags: [String] = [], note: String = "", parking: String = "", nearby: NearbySnapshot? = nil, weather: WeatherSnapshot? = nil, place: Place? = nil) {
        self.id = id
        self.ts = ts
        self.lat = lat
        self.lon = lon
        self.acc = acc
        self.fixTs = fixTs
        self.name = name
        self.tags = tags
        self.note = note
        self.parking = parking
        self.nearby = nearby
        self.weather = weather
        self.place = place
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = (try? c.decode(String.self, forKey: .id)) ?? ""
        guard !id.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Pin needs an id"))
        }
        guard let lat = try? c.decode(Double.self, forKey: .lat), let lon = try? c.decode(Double.self, forKey: .lon), lat.isFinite, lon.isFinite else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Pin needs coordinates"))
        }
        self.id = id
        self.ts = (try? c.decode(Double.self, forKey: .ts)) ?? 0
        self.lat = lat
        self.lon = lon
        self.acc = try? c.decodeIfPresent(Double.self, forKey: .acc) ?? nil
        self.fixTs = try? c.decodeIfPresent(Double.self, forKey: .fixTs) ?? nil
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""
        self.tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        self.note = (try? c.decode(String.self, forKey: .note)) ?? ""
        self.parking = (try? c.decode(String.self, forKey: .parking)) ?? ""
        if (try? c.decodeNil(forKey: .nearby)) == true {
            self.nearby = nil
        } else {
            self.nearby = try? c.decode(NearbySnapshot.self, forKey: .nearby)
        }
        if (try? c.decodeNil(forKey: .weather)) == true {
            self.weather = nil
        } else {
            self.weather = try? c.decode(WeatherSnapshot.self, forKey: .weather)
        }
        if (try? c.decodeNil(forKey: .place)) == true {
            self.place = nil
        } else {
            self.place = try? c.decode(Place.self, forKey: .place)
        }
    }
}

public enum ImportError: Error, Equatable {
    case notABackup
}

public struct ImportResult: Equatable, Sendable {
    public var pins: [Pin]
    public var added: Int
    public var skipped: Int
}

public func importPins(existing: [Pin], data: Data) throws -> ImportResult {
    let obj = try JSONSerialization.jsonObject(with: data)
    let array: [Any]
    if let dict = obj as? [String: Any] {
        guard let pins = dict["pins"] as? [Any] else { throw ImportError.notABackup }
        array = pins
    } else if let pins = obj as? [Any] {
        array = pins
    } else {
        throw ImportError.notABackup
    }
    var merged = existing
    var added = 0
    var skipped = 0
    for item in array {
        guard JSONSerialization.isValidJSONObject(item),
              let itemData = try? JSONSerialization.data(withJSONObject: item),
              let pin = try? JSONDecoder().decode(Pin.self, from: itemData) else {
            skipped += 1
            continue
        }
        if merged.contains(where: { $0.id == pin.id }) {
            skipped += 1
            continue
        }
        merged.append(pin)
        added += 1
    }
    return ImportResult(pins: merged, added: added, skipped: skipped)
}

public struct PinStore: Sendable {
    public let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("spots.json")
    }

    public func load() -> [Pin] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([Pin].self, from: data)
        } catch {
            let aside = fileURL.deletingLastPathComponent().appendingPathComponent("spots.json.unreadable-\(UUID().uuidString)")
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            return []
        }
    }

    public func save(_ pins: [Pin]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(pins)
        try data.write(to: fileURL, options: .atomic)
    }
}

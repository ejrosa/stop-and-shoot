import XCTest
@testable import StopAndShootLogic

final class LogicTests: XCTestCase {
    func testFormatCoord() {
        XCTAssertEqual(formatCoord(40.7128), "40.7128")
        XCTAssertEqual(formatCoord(-74.006), "-74.006")
        XCTAssertEqual(formatCoord(1.2345674), "1.234567")
        XCTAssertEqual(formatCoord(1.2345675), "1.234568")
        XCTAssertEqual(formatCoord(0.5), "0.5")
        XCTAssertEqual(formatCoord(0), "0")
        XCTAssertEqual(formatCoord(-0.0), "0")
        XCTAssertEqual(jsEncodeURIComponent("a b"), "a%20b")
        XCTAssertEqual(jsEncodeURIComponent("[out:json]"), "%5Bout%3Ajson%5D")
    }

    func testNoSeededPinsAndExistingDataSurvivesImport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = PinStore(directory: directory)
        XCTAssertEqual(store.load(), [])
        let kept = Pin(id: "keep-me", ts: 10, lat: 1, lon: 2, note: "mine")
        try store.save([kept])
        let backup = """
        {"app":"Stop & Shoot","exported":"2026-01-01T00:00:00.000Z","pins":[
          {"id":"keep-me","ts":99,"lat":5,"lon":5,"note":"do not overwrite"},
          {"id":"imported","ts":11,"lat":10.5,"lon":-10.25,"name":"Imported","tags":["Scenic"],"note":"hi","parking":"lot","nearby":null,"weather":null,"place":null},
          {"lat":1,"lon":2},
          {"id":"bad","lat":"nope","lon":2}
        ]}
        """.data(using: .utf8)!
        let result = try importPins(existing: store.load(), data: backup)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.skipped, 3)
        XCTAssertEqual(result.pins.first { $0.id == "keep-me" }?.note, "mine")
        try store.save(result.pins)
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.first { $0.id == "imported" }?.note, "hi")
        XCTAssertThrowsError(try importPins(existing: [], data: Data("{}".utf8)))
    }

    func testCorruptStoreIsQuarantinedRatherThanDeleted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = PinStore(directory: directory)
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertEqual(store.load(), [])
        let leftovers = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let quarantined = leftovers.filter { $0.lastPathComponent.hasPrefix("spots.json.unreadable-") }
        XCTAssertEqual(quarantined.count, 1)
        XCTAssertEqual(try String(contentsOf: quarantined[0], encoding: .utf8), "not json")
        try store.save([Pin(id: "new", ts: 1, lat: 3, lon: 4, note: "kept")])
        XCTAssertEqual(store.load().map(\.id), ["new"])
        let leftoversAfter = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(leftoversAfter.filter { $0.lastPathComponent.hasPrefix("spots.json.unreadable-") }.count, 1)
    }

    func testMakePinRoundsFixAndSpeechOmitsCoordinates() {
        let now = Date(timeIntervalSince1970: 1_782_000_000)
        let fix = LocationFix(latitude: 40.71281234, longitude: -74.00681234, horizontalAccuracy: 8.4, timestamp: now.addingTimeInterval(-2))
        guard case .success(let pin) = makePin(id: "p", fix: fix, note: "bridge\0", tags: [" Scenic ", "Scenic", ""], now: now) else {
            return XCTFail("expected a pin")
        }
        XCTAssertEqual(formatCoord(pin.lat), "40.712812")
        XCTAssertEqual(formatCoord(pin.lon), "-74.006812")
        XCTAssertEqual(pin.acc, 8)
        XCTAssertEqual(pin.note, "bridge")
        XCTAssertEqual(pin.tags, ["Scenic"])
        let speech = Speech.saved(pin: pin, locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertTrue(speech.hasPrefix("Spot saved at "))
        XCTAssertTrue(speech.contains("accuracy 8 meters"))
        XCTAssertFalse(speech.contains("40.712812"))
        XCTAssertFalse(speech.contains("-74.006812"))
        XCTAssertFalse(speech.contains("bridge"))
        let poor = Pin(id: "p", ts: pin.ts, lat: pin.lat, lon: pin.lon, acc: 150)
        XCTAssertTrue(Speech.saved(pin: poor, locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(secondsFromGMT: 0)!).contains("Check the map when you are parked."))
        XCTAssertEqual(makePin(id: "x", fix: LocationFix(latitude: 1, longitude: 2, horizontalAccuracy: -1, timestamp: now), note: nil, tags: [], now: now), .failure(.invalidFix))
        XCTAssertEqual(makePin(id: "x", fix: LocationFix(latitude: 91, longitude: 0, horizontalAccuracy: 5, timestamp: now), note: nil, tags: [], now: now), .failure(.invalidFix))
        XCTAssertEqual(Speech.failed(.permissionDenied), "Couldn't save the spot. Location permission is off.")
        XCTAssertEqual(MarkingPolicy.freshFixMaxAge, 15)
        XCTAssertEqual(MarkingPolicy.fixTimeout, 20)
    }

    func testMarkLinkIgnoresCoordinates() {
        let left = parseMarkLink(URL(string: "stopandshoot://mark?lat=1&lon=2&note=Hello%20there&tag=Scenic")!)
        let right = parseMarkLink(URL(string: "stopandshoot://mark?lat=9&lon=8&note=Hello%20there&tag=Scenic")!)
        XCTAssertEqual(left, right)
        XCTAssertEqual(left?.note, "Hello there")
        XCTAssertEqual(left?.tags, ["Scenic"])
        XCTAssertNil(parseMarkLink(URL(string: "https://example.com/?mark=1&note=Hi")!))
        XCTAssertEqual(parseMarkLink(URL(string: "stopandshoot://mark")!), MarkLink(note: nil, tags: []))
        XCTAssertNil(parseMarkLink(URL(string: "stopandshoot://help")!))
    }

    func testShortTimeAndCautionsMatchWebRules() {
        var parts = DateComponents()
        parts.calendar = Calendar(identifier: .gregorian)
        parts.timeZone = TimeZone(identifier: "America/New_York")
        parts.year = 2026
        parts.month = 6
        parts.day = 21
        parts.hour = 15
        parts.minute = 42
        let afternoon = parts.date!
        XCTAssertEqual(shortTime(afternoon, locale: Locale(identifier: "en_US_POSIX"), timeZone: parts.timeZone!), "3:42 PM")

        let locale = Locale(identifier: "en_US_POSIX")
        let zone = TimeZone(secondsFromGMT: 0)!
        let sunset = Date(timeIntervalSince1970: 1_700_000_000)
        let sunrise = sunset.addingTimeInterval(-12 * 3600)
        let dark = SunTimes(sunrise: sunrise, sunset: sunset, solarNoon: nil, goldenMorningEnd: nil, goldenEveningStart: nil, blueMorningStart: nil, blueMorningEnd: nil, blueEveningStart: nil, blueEveningEnd: nil)
        let darkLines = cautions(now: sunset.addingTimeInterval(60), sun: dark, weather: nil, accuracyMeters: nil, timeZone: zone, locale: locale)
        XCTAssertEqual(darkLines, ["It's dark now (sunset \(shortTime(sunset, locale: locale, timeZone: zone))). Pick a lit, open pull-off and keep your hazards and headlights in mind."])

        let soon = cautions(now: sunset.addingTimeInterval(-30 * 60), sun: dark, weather: nil, accuracyMeters: 100, timeZone: zone, locale: locale)
        XCTAssertEqual(soon.count, 1)
        XCTAssertTrue(soon[0].contains("less than 75 minutes away"))
        XCTAssertFalse(soon[0].contains("It's dark now"))

        let now = sunset.addingTimeInterval(-4 * 3600)
        let midday = SunTimes(sunrise: now.addingTimeInterval(-2 * 3600), sunset: now.addingTimeInterval(4 * 3600), solarNoon: now, goldenMorningEnd: nil, goldenEveningStart: nil, blueMorningStart: nil, blueMorningEnd: nil, blueEveningStart: nil, blueEveningEnd: nil)
        let weather = WeatherSnapshot(t: 70.2, feels: 71, code: 95, wind: 10, gust: 30, precip: 0.1, vis: 10000, rainChance: 80, uv: 8, at: 0)
        XCTAssertEqual(weatherLine(weather), "Thunderstorm · 70°F · feels 71°F · wind 10 mph (gusts 30) · 80% rain today")
        let lines = cautions(now: now, sun: midday, weather: weather, accuracyMeters: 150, timeZone: zone, locale: locale)
        XCTAssertEqual(lines, [
            "Thunderstorm reported. Lightning risk: stay in the car, skip exposed spots and tripods.",
            "Gusts around 30 mph. Watch car doors and weigh down the tripod.",
            "Rain likely (80%). Soft shoulders can be muddy; protect gear.",
            "High UV today (8).",
            "GPS accuracy was about 150 m, so the pin may be off. Double-check on the map."
        ])
        let icy = WeatherSnapshot(t: 34, code: 0, at: 0)
        XCTAssertEqual(cautions(now: now, sun: midday, weather: icy, accuracyMeters: nil, timeZone: zone, locale: locale), [
            "Near or below freezing: shoulders and bridges may be icy."
        ])
        XCTAssertTrue(TravelCopy.parkingDisclaimer.contains("aren't in any reliable public data"))
        XCTAssertFalse(TravelCopy.lookupDisclosure.localizedCaseInsensitiveContains("never leave"))
        XCTAssertTrue(TravelCopy.siriLimits.contains("not always-on listening"))
        XCTAssertTrue(TravelCopy.siriLimits.contains("While Using"))
        XCTAssertTrue(TravelCopy.noGrok.contains("does not"))
        XCTAssertEqual(lookupsEnabled(stored: nil), true)
        XCTAssertEqual(lookupsEnabled(stored: false), false)
    }

    func testExportsRoundTripAndEscape() throws {
        var parts = DateComponents()
        parts.calendar = Calendar(identifier: .gregorian)
        parts.timeZone = TimeZone(secondsFromGMT: 0)
        parts.year = 2026
        parts.month = 6
        parts.day = 21
        parts.hour = 15
        parts.minute = 42
        let now = parts.date!
        let pin = Pin(id: "p", ts: now.timeIntervalSince1970 * 1000, lat: 40.7128, lon: -74.006, acc: 8, fixTs: now.timeIntervalSince1970 * 1000, name: "A & B", tags: ["Scenic"], note: "say \"hi\"", parking: "lot")
        XCTAssertEqual(exportFileName(extension: "json", now: now), "spots-2026-06-21.json")
        let csv = exportCSV(pins: [pin])
        XCTAssertTrue(csv.contains("\"say \"\"hi\"\"\""))
        XCTAssertTrue(csv.hasPrefix("time_iso,lat,lon,accuracy_m,name,tags,note,parking_cautions\n"))
        let gpx = exportGPX(pins: [pin], appName: "Stop & Shoot")
        XCTAssertTrue(gpx.contains("A &amp; B"))
        XCTAssertTrue(gpx.contains("lat=\"40.7128\" lon=\"-74.006\""))
        XCTAssertTrue(gpx.contains("say &quot;hi&quot;"))
        let data = try exportJSON(pins: [pin], appName: AppIdentity.name, exportedAt: now)
        let imported = try importPins(existing: [], data: data)
        XCTAssertEqual(imported.added, 1)
        XCTAssertEqual(imported.pins[0].fixTs != nil, true)
        XCTAssertEqual(imported.pins[0].note, "say \"hi\"")
        let shared = shareText(pin: pin)
        XCTAssertTrue(shared.contains("maps.apple.com"))
        XCTAssertFalse(shared.contains("google.com"))
    }

    func testLookupHostsMatchTheFixture() throws {
        let data = try fixture("network_hosts")
        let hosts = try JSONDecoder().decode([String].self, from: data)
        XCTAssertEqual(Set(hosts), Set(ServiceEndpoints.allLookupURLs))
        let request = nrelRequest(lat: 40.7128, lon: -74.006, apiKey: ServiceEndpoints.nrelDemoAPIKey)
        XCTAssertTrue(request?.url.absoluteString.contains("api_key=DEMO_KEY") == true)
        XCTAssertTrue(request?.url.absoluteString.contains("latitude=40.7128") == true)
        XCTAssertTrue(request?.url.absoluteString.contains("longitude=-74.006") == true)
        XCTAssertEqual(request?.headers["User-Agent"], AppIdentity.userAgent)
        let custom = nrelRequest(lat: 1, lon: 2, apiKey: "LOCAL_KEY")
        XCTAssertTrue(custom?.url.absoluteString.contains("api_key=LOCAL_KEY") == true)
        let query = overpassQuery(lat: 40.7128, lon: -74.006)
        XCTAssertTrue(query.contains("amenity\"=\"fuel\""))
        XCTAssertTrue(query.contains("40.7128"))
        XCTAssertTrue(query.contains("-74.006"))
        let body = overpassRequest(mirror: ServiceEndpoints.overpassMirrors[0], lat: 40.7128, lon: -74.006)?.body ?? ""
        XCTAssertTrue(body.contains("40.7128"))
        XCTAssertTrue(body.contains("-74.006"))
    }

    func testSunTimesMatchTheWebsite() throws {
        struct Golden: Decodable {
            var iso: String
            var lat: Double
            var lon: Double
            var sunrise: String?
            var sunset: String?
            var solarNoon: String?
            var goldenMorningEnd: String?
            var goldenEveningStart: String?
            var blueMorningStart: String?
            var blueMorningEnd: String?
            var blueEveningStart: String?
            var blueEveningEnd: String?
        }
        let cases = try JSONDecoder().decode([Golden].self, from: fixture("sun_golden"))
        XCTAssertEqual(cases.count, 4)
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for item in cases {
            let input = try XCTUnwrap(parser.date(from: item.iso))
            let sun = sunTimes(date: input, lat: item.lat, lon: item.lon)
            expect(sun.sunrise, item.sunrise, parser)
            expect(sun.sunset, item.sunset, parser)
            expect(sun.solarNoon, item.solarNoon, parser)
            expect(sun.goldenMorningEnd, item.goldenMorningEnd, parser)
            expect(sun.goldenEveningStart, item.goldenEveningStart, parser)
            expect(sun.blueMorningStart, item.blueMorningStart, parser)
            expect(sun.blueMorningEnd, item.blueMorningEnd, parser)
            expect(sun.blueEveningStart, item.blueEveningStart, parser)
            expect(sun.blueEveningEnd, item.blueEveningEnd, parser)
        }
    }

    func testEnrichmentSendsCoordinatesAndCanStayOnDevice() async {
        let pin = Pin(id: "spot", ts: 1, lat: 40.7128, lon: -74.006)
        let off = await enrich(pin: pin, force: false, online: true, lookupsEnabled: false, apiKey: "DEMO_KEY", client: ScriptedHTTP(), sleepMilliseconds: { _ in }, onUpdate: { _ in })
        XCTAssertEqual(off.nearby?.status, "off")
        XCTAssertEqual(off.lat, pin.lat)

        let asleep = SleepLog()
        let client = ScriptedHTTP()
        client.handler = { request in
            let url = request.url.absoluteString
            if url.contains("/reverse") { return Data(Self.reverseJSON.utf8) }
            if url.contains("open-meteo.com") { return Data(Self.weatherJSON.utf8) }
            if url.contains("nearest.json") { return Data(Self.nrelJSON.utf8) }
            if url.contains("overpass-api.de") { throw FetchFailure.badStatus }
            if url.contains("overpass") { return Data(Self.overpassJSON.utf8) }
            return nil
        }
        var snapshots: [Pin] = []
        let updated = await enrich(pin: pin, force: false, online: true, lookupsEnabled: true, apiKey: "DEMO_KEY", client: client, sleepMilliseconds: { milliseconds in
            await asleep.add(milliseconds)
        }, clock: { Date(timeIntervalSince1970: 1_700_000_000) }, onUpdate: { pin in
            snapshots.append(pin)
        })
        XCTAssertEqual(updated.place?.short, "Main St, Town, State")
        XCTAssertEqual(updated.name, "Main St, Town, State")
        XCTAssertEqual(updated.nearby?.status, "ok")
        XCTAssertEqual(updated.nearby?.sources, [SourceName.doe, SourceName.overpass])
        XCTAssertEqual(updated.nearby?.ev.map(\.src), [SourceName.doe])
        XCTAssertEqual(updated.nearby?.fuel.first?.name, "Corner Gas")
        XCTAssertEqual(updated.nearby?.wc.first?.name, "Restroom (unnamed)")
        XCTAssertEqual(updated.nearby?.parking.first?.facts, ["fee: no", "access: yes"])
        XCTAssertTrue(client.requests.contains { $0.url.absoluteString.contains("lat=40.7128") })
        XCTAssertTrue(client.requests.contains { $0.url.absoluteString.contains("latitude=40.7128") && $0.url.absoluteString.contains("longitude=-74.006") })
        XCTAssertTrue(client.requests.contains { ($0.body ?? "").contains("40.7128") && ($0.body ?? "").contains("-74.006") })
        XCTAssertTrue(client.requests.allSatisfy { $0.headers["User-Agent"] == AppIdentity.userAgent })
        XCTAssertFalse(client.requests.contains { $0.url.absoluteString.contains("nominatim.openstreetmap.org/search") })
        let noSleeps = await asleep.snapshot()
        XCTAssertEqual(noSleeps, [])
        XCTAssertGreaterThan(snapshots.count, 2)

        let fallback = ScriptedHTTP()
        fallback.handler = { request in
            let url = request.url.absoluteString
            if url.contains("/reverse") { throw FetchFailure.badStatus }
            if url.contains("open-meteo.com") { throw FetchFailure.badStatus }
            if url.contains("nearest.json") { throw FetchFailure.badStatus }
            if url.contains("overpass") { throw FetchFailure.badStatus }
            if url.contains("amenity=fuel") && url.contains(nominatimViewbox(lat: 40.7128, lon: -74.006, delta: 0.035).prefix(8)) {
                return Data(Self.searchJSON.utf8)
            }
            if url.contains("nominatim.openstreetmap.org/search") { return Data("[]".utf8) }
            return nil
        }
        let sleeps = SleepLog()
        let found = await enrich(pin: pin, force: false, online: true, lookupsEnabled: true, apiKey: "DEMO_KEY", client: fallback, sleepMilliseconds: { milliseconds in
            await sleeps.add(milliseconds)
        }, onUpdate: { _ in })
        XCTAssertEqual(found.nearby?.status, "ok")
        XCTAssertEqual(found.nearby?.sources, [SourceName.nominatim])
        XCTAssertEqual(found.nearby?.fuel.first?.name, "Pump")
        XCTAssertEqual(found.nearby?.errors, [LookupErrorText.doe, LookupErrorText.overpass])
        XCTAssertEqual(found.name, "")
        let recordedSleeps = await sleeps.snapshot()
        XCTAssertEqual(recordedSleeps, [1100, 1100, 1100, 1100, 1100])
        XCTAssertTrue(fallback.requests.contains { $0.url.host == "nominatim.openstreetmap.org" && $0.url.absoluteString.contains("40.7128") })
    }

    func testMergeEVAndGate() async {
        let kept = POI(name: "A", lat: 1, lon: 1, addr: "", facts: [], mi: 1, src: "A")
        let duplicate = POI(name: "B", lat: 1, lon: 1, addr: "", facts: [], mi: 2, src: "B")
        let closer = POI(name: "C", lat: 2, lon: 2, addr: "", facts: [], mi: 0.2, src: "C")
        XCTAssertEqual(mergeEV([kept], [duplicate, closer]).map(\.src), ["C", "A"])
        let gate = MarkGate()
        let entered = Flag()
        let task = Task {
            await gate.run { () -> String in
                await entered.set(true)
                try? await Task.sleep(nanoseconds: 200_000_000)
                return "first"
            }
        }
        let deadline = Date().addingTimeInterval(2)
        while await entered.get() == false {
            if Date() > deadline {
                XCTFail("mark did not start")
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let second = await gate.run { "second" }
        let first = await task.value
        XCTAssertNil(second)
        XCTAssertEqual(first, "first")
    }

    private func expect(_ actual: Date?, _ golden: String?, _ parser: ISO8601DateFormatter, file: StaticString = #filePath, line: UInt = #line) {
        switch (actual, golden.flatMap(parser.date(from:))) {
        case (nil, nil):
            return
        case let (left?, right?):
            XCTAssertEqual(left.timeIntervalSince1970, right.timeIntervalSince1970, accuracy: 0.05, file: file, line: line)
        default:
            XCTFail("expected \(golden ?? "nil") got \(String(describing: actual))", file: file, line: line)
        }
    }

    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle.module
        let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: "json")
        return try Data(contentsOf: try XCTUnwrap(url, "Missing \(name). Bundle urls: \(bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])"))
    }

    private static let reverseJSON = #"{"display_name":"Main St, Town, State, Country","address":{"road":"Main St","city":"Town","state":"State"}}"#
    private static let weatherJSON = #"{"current":{"temperature_2m":70.2,"apparent_temperature":71,"weather_code":95,"wind_speed_10m":10,"wind_gusts_10m":30,"precipitation":0.1,"visibility":10000},"daily":{"precipitation_probability_max":[80],"uv_index_max":[8]}}"#
    private static let nrelJSON = #"{"fuel_stations":[{"station_name":"Town Charger","latitude":40.73,"longitude":-74.02,"street_address":"1 Main","city":"Town","access_days_time":"24 hours","ev_connector_types":["J1772"],"ev_level2_evse_num":2,"ev_network":"Example","distance":0.4}]}"#
    private static let overpassJSON = #"{"elements":[{"type":"node","lat":40.713,"lon":-74.007,"tags":{"amenity":"fuel","name":"Corner Gas","opening_hours":"24/7"}},{"type":"node","lat":40.714,"lon":-74.008,"tags":{"amenity":"toilets","access":"yes"}},{"type":"way","center":{"lat":40.712,"lon":-74.005},"tags":{"amenity":"parking","fee":"no","access":"yes"}},{"type":"node","lat":40.73,"lon":-74.02,"tags":{"amenity":"charging_station","socket:type2":"2"}}]}"#
    private static let searchJSON = #"[{"name":"Pump","lat":"40.713","lon":"-74.007","display_name":"Pump, Town, State"}]"#
}

private final class ScriptedHTTP: HTTPFetching {
    var requests: [HTTPRequest] = []
    var handler: ((HTTPRequest) throws -> Data?)?
    func send(_ request: HTTPRequest) async throws -> Data {
        requests.append(request)
        if let data = try handler?(request) { return data }
        throw FetchFailure.badStatus
    }
}

private actor SleepLog {
    private var values: [Int] = []
    func add(_ value: Int) { values.append(value) }
    func snapshot() -> [Int] { values }
}

private actor Flag {
    private var value = false
    func set(_ newValue: Bool) { value = newValue }
    func get() -> Bool { value }
}

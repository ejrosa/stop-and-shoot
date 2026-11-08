import Foundation

public func enrich(
    pin: Pin,
    force: Bool,
    online: Bool,
    lookupsEnabled: Bool,
    apiKey: String,
    client: HTTPFetching,
    sleepMilliseconds: @escaping (Int) async -> Void = { milliseconds in
        try? await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    },
    clock: @escaping () -> Date = Date.init,
    onUpdate: @escaping (Pin) async -> Void
) async -> Pin {
    var current = pin
    if !lookupsEnabled {
        if current.nearby == nil {
            current.nearby = NearbySnapshot(status: "off")
            await onUpdate(current)
        }
        return current
    }
    if !online {
        if current.nearby == nil {
            current.nearby = NearbySnapshot(status: "offline")
            await onUpdate(current)
        }
        return current
    }

    var loading = current.nearby ?? NearbySnapshot(status: "loading")
    loading.status = "loading"
    current.nearby = loading
    await onUpdate(current)

    if current.place == nil || force {
        if let request = nominatimReverseRequest(lat: current.lat, lon: current.lon),
           let data = try? await client.send(request),
           let place = try? parseNominatimReverse(data) {
            current.place = place
            if current.name.isEmpty { current.name = place.short }
            await onUpdate(current)
        }
    }
    if let request = openMeteoRequest(lat: current.lat, lon: current.lon),
       let data = try? await client.send(request),
       let weather = try? parseWeather(data, now: clock()) {
        current.weather = weather
        await onUpdate(current)
    }

    var buckets = NearbyBuckets()
    var errors: [String] = []
    var sources: [String] = []
    if let request = nrelRequest(lat: current.lat, lon: current.lon, apiKey: apiKey) {
        do {
            let data = try await client.send(request)
            let stations = try parseNREL(data, originLat: current.lat, originLon: current.lon)
            if !stations.isEmpty {
                buckets.ev = stations
                sources.append(SourceName.doe)
                current.nearby = NearbySnapshot(ev: buckets.ev, fuel: buckets.fuel, wc: buckets.wc, parking: buckets.parking, status: "loading", sources: sources)
                await onUpdate(current)
            }
        } catch {
            errors.append(LookupErrorText.doe)
        }
    }

    var overpassFailed = true
    for mirror in ServiceEndpoints.overpassMirrors {
        guard let request = overpassRequest(mirror: mirror, lat: current.lat, lon: current.lon) else { continue }
        do {
            let data = try await client.send(request)
            var parsed = try parseOverpass(data, originLat: current.lat, originLon: current.lon)
            parsed.ev = mergeEV(buckets.ev, parsed.ev)
            buckets = parsed
            sources.append(SourceName.overpass)
            overpassFailed = false
            break
        } catch {
            continue
        }
    }
    if overpassFailed { errors.append(LookupErrorText.overpass) }

    if overpassFailed {
        let categories: [(String, String)] = [("fuel", "fuel"), ("wc", "toilets"), ("ev", "charging_station")]
        for (kind, amenity) in categories {
            let existing: [POI]
            switch kind {
            case "fuel": existing = buckets.fuel
            case "wc": existing = buckets.wc
            default: existing = buckets.ev
            }
            if !existing.isEmpty { continue }
            await sleepMilliseconds(1100)
            do {
                let found = try await nominatimNearby(lat: current.lat, lon: current.lon, amenity: amenity, kind: kind, client: client, sleepMilliseconds: sleepMilliseconds)
                switch kind {
                case "fuel": buckets.fuel = found
                case "wc": buckets.wc = found
                default: buckets.ev = found
                }
                if !sources.contains(SourceName.nominatim) { sources.append(SourceName.nominatim) }
            } catch {
                continue
            }
        }
    }

    current.nearby = NearbySnapshot(
        ev: buckets.ev,
        fuel: buckets.fuel,
        wc: buckets.wc,
        parking: buckets.parking,
        status: sources.isEmpty ? "error" : "ok",
        errors: errors,
        sources: sources,
        at: clock().timeIntervalSince1970 * 1000
    )
    await onUpdate(current)
    return current
}

private func nominatimNearby(lat: Double, lon: Double, amenity: String, kind: String, client: HTTPFetching, sleepMilliseconds: (Int) async -> Void) async throws -> [POI] {
    guard let nearRequest = nominatimSearchRequest(lat: lat, lon: lon, amenity: amenity, delta: 0.035) else { throw FetchFailure.badStatus }
    let nearData = try await client.send(nearRequest)
    let near = try parseNominatimSearch(nearData, originLat: lat, originLon: lon, kind: kind)
    if !near.isEmpty { return near }
    await sleepMilliseconds(1100)
    guard let wideRequest = nominatimSearchRequest(lat: lat, lon: lon, amenity: amenity, delta: 0.15) else { throw FetchFailure.badStatus }
    let wideData = try await client.send(wideRequest)
    return try parseNominatimSearch(wideData, originLat: lat, originLon: lon, kind: kind)
}

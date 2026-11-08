import Foundation

public let knownTags = ["Photo spot", "Scenic", "Food", "Rest stop", "Hazard"]

private let wmo: [Int: String] = [
    0: "Clear", 1: "Mostly clear", 2: "Partly cloudy", 3: "Overcast",
    45: "Fog", 48: "Freezing fog", 51: "Light drizzle", 53: "Drizzle", 55: "Heavy drizzle",
    56: "Freezing drizzle", 57: "Freezing drizzle", 61: "Light rain", 63: "Rain", 65: "Heavy rain",
    66: "Freezing rain", 67: "Freezing rain", 71: "Light snow", 73: "Snow", 75: "Heavy snow",
    77: "Snow grains", 80: "Rain showers", 81: "Rain showers", 82: "Violent rain showers",
    85: "Snow showers", 86: "Snow showers", 95: "Thunderstorm", 96: "Thunderstorm with hail",
    99: "Thunderstorm with hail"
]

public func wmoLabel(_ code: Int) -> String? { wmo[code] }

private func jsRoundInt(_ value: Double) -> Int {
    Int(value.rounded(.toNearestOrAwayFromZero))
}

private func jsNumber(_ value: Double) -> String {
    if value.isFinite, value.rounded(.toNearestOrAwayFromZero) == value, abs(value) < 1e15 {
        return String(jsRoundInt(value))
    }
    return String(value)
}

public func weatherLine(_ weather: WeatherSnapshot) -> String {
    var parts: [String] = []
    if let code = weather.code, let label = wmoLabel(code), !label.isEmpty {
        parts.append(label)
    }
    if let temperature = weather.t { parts.append("\(jsRoundInt(temperature))°F") }
    if let feels = weather.feels { parts.append("feels \(jsRoundInt(feels))°F") }
    if let wind = weather.wind {
        var text = "wind \(jsRoundInt(wind)) mph"
        if let gust = weather.gust, gust != 0 {
            text += " (gusts \(jsRoundInt(gust)))"
        }
        parts.append(text)
    }
    if let rain = weather.rainChance { parts.append("\(jsNumber(rain))% rain today") }
    return parts.joined(separator: " · ")
}

public func cautions(now: Date, sun: SunTimes, weather: WeatherSnapshot?, accuracyMeters: Double?, timeZone: TimeZone, locale: Locale) -> [String] {
    var lines: [String] = []
    func hm(_ date: Date?) -> String {
        guard let date else { return "—" }
        return shortTime(date, locale: locale, timeZone: timeZone)
    }
    if let sunset = sun.sunset {
        let beforeSunrise = sun.sunrise.map { now < $0 } ?? false
        if now > sunset || beforeSunrise {
            lines.append("It's dark now (sunset \(hm(sunset))). Pick a lit, open pull-off and keep your hazards and headlights in mind.")
        } else if sunset.timeIntervalSince(now) / 60 < 75 {
            lines.append("Sunset at \(hm(sunset)), less than 75 minutes away. Plan how you'll get back to the car in low light.")
        }
    }
    if let weather {
        if let code = weather.code, [95, 96, 99].contains(code) {
            lines.append("Thunderstorm reported. Lightning risk: stay in the car, skip exposed spots and tripods.")
        }
        if weather.code.map({ [45, 48].contains($0) }) == true || (weather.vis ?? 1600) < 1600 {
            lines.append("Low visibility (fog/haze). Pull fully off the road and use lights when stopping.")
        }
        if weather.code.map({ [56, 57, 66, 67, 71, 73, 75, 77, 85, 86].contains($0) }) == true || (weather.t ?? 35) <= 34 {
            lines.append("Near or below freezing: shoulders and bridges may be icy.")
        }
        if let gust = weather.gust, gust >= 25 {
            lines.append("Gusts around \(jsRoundInt(gust)) mph. Watch car doors and weigh down the tripod.")
        }
        if (weather.precip ?? 0) > 0 || (weather.rainChance ?? 0) >= 60 {
            let rain = weather.rainChance.map { "\(jsNumber($0))%" } ?? "now"
            lines.append("Rain likely (\(rain)). Soft shoulders can be muddy; protect gear.")
        }
        if let feels = weather.feels, feels >= 95 {
            lines.append("Feels like \(jsRoundInt(feels))°F. Bring water; don't leave pets or gear in a hot car.")
        }
        if let uv = weather.uv, uv >= 7 {
            lines.append("High UV today (\(jsRoundInt(uv))).")
        }
    }
    if let accuracyMeters, accuracyMeters != 0, accuracyMeters > 100 {
        lines.append("GPS accuracy was about \(jsRoundInt(accuracyMeters)) m, so the pin may be off. Double-check on the map.")
    }
    return lines
}

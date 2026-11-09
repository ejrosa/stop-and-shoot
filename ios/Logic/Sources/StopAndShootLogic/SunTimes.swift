import Foundation

public struct SunTimes: Equatable, Sendable {
    public var sunrise: Date?
    public var sunset: Date?
    public var solarNoon: Date?
    public var goldenMorningEnd: Date?
    public var goldenEveningStart: Date?
    public var blueMorningStart: Date?
    public var blueMorningEnd: Date?
    public var blueEveningStart: Date?
    public var blueEveningEnd: Date?
}

public func sunTimes(date: Date, lat: Double, lon: Double) -> SunTimes {
    let rad = Double.pi / 180
    let j1970 = 2440588.0
    let j2000 = 2451545.0
    let obliquity = rad * 23.4397
    let j0 = 0.0009

    func toDays(_ value: Date) -> Double {
        value.timeIntervalSince1970 * 1000 / 86_400_000 - 0.5 + j1970 - j2000
    }
    func fromJulian(_ julian: Double) -> Date? {
        let milliseconds = (julian + 0.5 - j1970) * 86_400_000
        guard milliseconds.isFinite else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
    func jsRound(_ value: Double) -> Double { floor(value + 0.5) }
    func meanAnomaly(_ days: Double) -> Double { rad * (357.5291 + 0.98560028 * days) }
    func eclipticLongitude(_ anomaly: Double) -> Double {
        let center = rad * (1.9148 * sin(anomaly) + 0.02 * sin(2 * anomaly) + 0.0003 * sin(3 * anomaly))
        return anomaly + center + rad * 102.9372 + Double.pi
    }

    let lw = rad * -lon
    let phi = rad * lat
    let days = toDays(date)
    let cycle = jsRound(days - j0 - lw / (2 * Double.pi))
    let solarDays = j0 + lw / (2 * Double.pi) + cycle
    let anomaly = meanAnomaly(solarDays)
    let longitude = eclipticLongitude(anomaly)
    let declination = asin(sin(obliquity) * sin(longitude))
    func transit(_ solarDayValue: Double) -> Double {
        j2000 + solarDayValue + 0.0053 * sin(anomaly) - 0.0069 * sin(2 * longitude)
    }
    let noon = transit(solarDays)
    func event(_ altitude: Double) -> (Date?, Date?) {
        let argument = (sin(altitude * rad) - sin(phi) * sin(declination)) / (cos(phi) * cos(declination))
        guard argument.isFinite, (-1...1).contains(argument) else { return (nil, nil) }
        let hourAngle = acos(argument)
        let setJulian = transit(j0 + (hourAngle + lw) / (2 * Double.pi) + cycle)
        return (fromJulian(noon - (setJulian - noon)), fromJulian(setJulian))
    }

    let (sunrise, sunset) = event(-0.833)
    let (goldenMorningEnd, goldenEveningStart) = event(6)
    let (blueMorningStart, blueEveningEnd) = event(-6)
    let (blueMorningEnd, blueEveningStart) = event(-4)
    return SunTimes(
        sunrise: sunrise,
        sunset: sunset,
        solarNoon: fromJulian(noon),
        goldenMorningEnd: goldenMorningEnd,
        goldenEveningStart: goldenEveningStart,
        blueMorningStart: blueMorningStart,
        blueMorningEnd: blueMorningEnd,
        blueEveningStart: blueEveningStart,
        blueEveningEnd: blueEveningEnd
    )
}

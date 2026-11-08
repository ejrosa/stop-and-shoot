import Foundation

public enum AppIdentity {
    public static let name = "Stop & Shoot"
    public static let marketingVersion = "0.1.0"
    public static let buildNumber = "1"
    /// Provisional. Replace with an identifier you control before signing or TestFlight.
    public static let bundleIdentifier = "dev.provisional.stopandshoot"
    public static let userAgent = "StopAndShoot-iOS/\(marketingVersion) (https://github.com/ejrosa/stop-and-shoot)"
}

public enum MarkingPolicy {
    /// Same fresh-fix window the website uses.
    public static let freshFixMaxAge: TimeInterval = 15
    public static let fixTimeout: TimeInterval = 20
}

public enum TravelCopy {
    public static let driveSafe = "Don't tap or read this app while the car is moving. Ask Siri to mark a spot, wait until you are parked, or hand the phone to a passenger."
    public static let locationUse = "Location is used when you mark a spot and while the app is on screen, so the next mark can use a recent fix. It is not tracked in the background. The saved fix includes the time and the accuracy radius in meters."
    public static let lookupShort = "If you are online and lookups are on, saving or opening a spot sends that spot's coordinates to map, fuel, and weather services. The spot itself stays on this phone."
    public static let lookupDisclosure = "Saved spots stay in a file on this iPhone. If lookups are on and you are online, the app sends that spot's coordinates to OpenStreetMap (Nominatim and Overpass), the U.S. Department of Energy alternative-fuel station list, and Open-Meteo. Those services are not part of Stop & Shoot. Turning lookups off keeps new marks on the phone only. Opening a map, sharing a spot, or copying coordinates also sends them where you choose."
    public static let siriLimits = "Asking Siri to mark a spot runs an App Shortcut. This is not always-on listening. This app does not record audio in the background and does not hear you until you invoke Siri yourself, or until you tap Speak on a saved spot. Siri opens Stop & Shoot to read location because permission is While Using the App, not Always. If you have not allowed location, nothing is saved. A shorter phrase you add in Apple's Shortcuts app is still a shortcut you run, not a listener inside this app."
    public static let noGrok = "Stop & Shoot does not integrate Hey Grok or any in-app wake word."
    public static let parkingDisclaimer = "Parking rules aren't in any reliable public data. Always confirm on posted signs (no-parking zones, hours, permits, towing, private property). Write what you see below."
    public static let everyStop = [
        "Pull fully off the road; shoulders are for emergencies in many states.",
        "Watch for No Trespassing / private property signs before walking in.",
        "Check footing near water, ditches, and soft shoulders; mind traffic when you get out.",
        "Lock the car and keep gear out of sight."
    ]
}

public func lookupsEnabled(stored: Bool?) -> Bool {
    stored ?? true
}

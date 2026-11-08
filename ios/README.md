# Stop & Shoot for iPhone

Initial native iPhone app. It is a foundation you can build in Xcode. It is not submitted to the App Store, and this repository does not contain a signing team, certificate, or provisioning profile.

## Why this is native rather than Capacitor

The website stays the deployed app. Wrapping it in Capacitor would copy the same JavaScript into a WKWebView and still need a native target for the parts that matter on the road:

- App Shortcuts and Siri are Swift. A web view cannot register them.
- Spoken confirmation needs `AVSpeechSynthesizer`. Browser speech in a web view is unreliable unless the user has just tapped the page, which a Siri launch does not guarantee.
- Spots need a file the system will not purge. WKWebView `localStorage` can be evicted, and an App Shortcut cannot write into that store.
- Core Location reports the fix time and horizontal accuracy directly. The web geolocation bridge is a second, less direct path.
- A service worker inside the web view is a separate cache from the deployed site and is easy to get wrong.

The shared rules (sun times, cautions, nearby parsing, export, and the decision to send or not send coordinates) live in `ios/Logic` and are tested on Linux. The SwiftUI app is the iPhone shell around that package. The website is not rewritten.

## What this foundation does

- One large **Mark this spot** button. Saving does not open a form.
- Stores each spot on this iPhone: coordinates rounded to 6 decimal places, save time, GPS sample time, and accuracy in meters.
- Speaks the result, including the clock time and accuracy. Poor accuracy (over 100 meters) says to check the map when parked. The spoken line does not read the coordinates aloud.
- Keeps spots in `Application Support/StopAndShoot/spots.json`. Import merges a JSON backup by id and does not delete or overwrite spots already saved.
- Exports JSON, GPX, and CSV in the same shape as the website.
- Notes, tags, and a parking note on the spot screen, for when you are parked.
- On-device dictation only after you tap Speak, and only when the phone supports on-device recognition. There is no server transcription fallback.
- Nearby EV, gas, restrooms, and OpenStreetMap parking, with the source on each row. Cautions use the same weather, light, and GPS rules as the website. Parking laws are not invented.
- A lookups switch. Off means a new mark is not sent to the lookup services.
- An App Shortcut that opens the app, reads a While Using location fix, saves the spot, and lets Siri speak the result.

## Siri and location limits

This is not always-on listening. The app does not listen for a wake word. Hey Siri is Apple's Siri, which you invoke. Hey Grok is not integrated.

The shortcut phrases are:

- “Mark spot in Stop & Shoot”
- “Mark a spot with Stop & Shoot”
- “Save this spot in Stop & Shoot”

Siri may pronounce the name as “Stop and Shoot.” If a phrase does not run, add the Mark Spot action in Shortcuts and give that shortcut your own phrase. That phrase is still a shortcut you run.

`openAppWhenRun` is true. Location permission is While Using the App, not Always. iOS will not give this app a GPS fix while it is suspended, so Siri has to open Stop & Shoot. The screen can wake. You do not need to tap if location was already allowed. Allow location once while parked before you depend on it on the road. The first system prompt needs a tap.

There is no background location mode and no Always authorization. A mark that is sent to the background before a fix arrives can fail, and the app says it could not get GPS. The app does not keep a running GPS log.

`stopandshoot://mark` opens the app and marks from the phone's GPS. Coordinates in that URL are ignored, so another app cannot write a fake pin. `stopandshoot://mark?note=` can attach words. The website's `?mark=1` link still saves into the browser list, which is a different store.

The optional Note field on the shortcut is for the Shortcuts editor. It is not part of the spoken phrase. If a device build shows Siri asking a follow-up, clear that field in Shortcuts. That behavior was not run on a phone here.

## Build on a Mac

1. Install Xcode 16 or newer. The project uses Xcode 16 synchronized folders and iOS 17.
2. Open `ios/StopAndShoot.xcodeproj`.
3. Let Xcode resolve the local Swift package `ios/Logic`. It has no remote dependencies.
4. In Signing & Capabilities, choose your Personal Team or a paid team. Do not commit the team id. Put local overrides in `ios/Config/Local.xcconfig` (gitignored):

   ```
   DEVELOPMENT_TEAM = YOUR_TEAM
   PRODUCT_BUNDLE_IDENTIFIER = com.yourname.stopandshoot
   ```

5. The committed bundle id is `dev.provisional.stopandshoot`. It is provisional. Change it to an id you control before TestFlight or the App Store. Changing it later creates a different app.
6. Select an iPhone simulator or a phone and run the StopAndShoot scheme.
7. On first launch, read the notice and tap Continue, then allow location While Using the App.
8. Mark a spot and confirm the spoken result, the saved time, and the accuracy.
9. Say one of the Siri phrases above after the app has been opened at least once so iOS has registered the shortcut.

Logic tests on a Mac, without launching the simulator:

```bash
swift test --package-path ios/Logic
bash ios/Scripts/check.sh
```

A simulator or device build:

```bash
xcodebuild -project ios/StopAndShoot.xcodeproj -scheme StopAndShoot -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Pick a simulator name that exists on that Mac. This environment has no macOS, Xcode, or iPhone, so that command was not run here.

Version `0.1.0` (build 1) is the app marketing version. The website is versioned separately and is currently 1.0.1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `ios/Config/Provisional.xcconfig`, and bump `AppIdentity.marketingVersion` in `ios/Logic/Sources/StopAndShootLogic/Identity.swift` so the Nominatim user agent matches.

## What was tested without a Mac

`bash ios/Scripts/check.sh` runs the Python audit, `node --check` on the website, a sun-time comparison against `app.js`, and `swift test` for the logic package. Those tests cover storage, import that does not destroy existing spots, coordinate rounding, spoken text, Siri link parsing, caution wording, export files, and the lookup requests (including that coordinates are present in those requests).

Not tested here: compiling the SwiftUI target, the simulator, a real GPS fix, Siri, the microphone, the speaker, backgrounding, or TestFlight.

## Not in this foundation

- App Store submission, screenshots, a privacy-policy URL, or a developer-account enrollment
- CarPlay, widgets, Apple Watch, iCloud sync, or a shared database with the website
- Background or Always location
- A wake word inside the app
- Invented parking rules, or a map drawn inside the app (Open in Maps and Navigate hand the coordinates to Apple Maps when you tap them)
- Replacing the public NREL `DEMO_KEY` (see the readiness checklist)

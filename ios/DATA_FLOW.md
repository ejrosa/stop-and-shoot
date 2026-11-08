# Where spot data goes

Stop & Shoot has no account and no app server. A saved spot is not uploaded as a backup by the app. Coordinates do leave the device when a lookup, map link, or share action says they do. Nothing below claims that coordinates never leave the device.

The website and the iPhone app do not share a store. Moving spots is a JSON export from one and an import into the other. Import adds pins whose ids are new. It does not delete pins already saved.

## Stays on the device

| Data | Website | iPhone app |
| --- | --- | --- |
| Spot list | `localStorage` key `sas.pins.v1` in that browser profile (Safari and an installed Home Screen icon do not share it) | `Application Support/StopAndShoot/spots.json` |
| Notes, tags, parking text | Same browser record | Same file |
| Safety acknowledgement | `localStorage` | `UserDefaults` key `sas.ios.safetyOK` only. No coordinates are stored there. |
| Lookups on or off | Always on when online | `UserDefaults` key `sas.ios.lookupsEnabled`. Missing means on. |
| Dictation audio | Browser speech recognition, which may use Apple's servers depending on the keyboard or browser | Microphone audio is used only while Speak is on. Recognition is requested on-device. Audio is not written to the spot file. If on-device recognition is unavailable, the app asks you to type. |

A normal iPhone backup can include the app's local file if you back up the phone. That is the device backup, not a Stop & Shoot service. The iPhone app does not use iCloud, analytics, or an advertising identifier.

New website installs are not given a sample pin. Pins already stored under `sas.pins.v1` are left as they are. This change does not rewrite git history; an older commit still contains a removed test pin.

## Leaves the device

These calls happen only for a spot you saved or opened, and only when lookups are on (the website has no off switch) and the device is online. Each request includes that spot's latitude and longitude.

| Service | What is sent | Why |
| --- | --- | --- |
| `https://nominatim.openstreetmap.org/reverse` | Coordinates, zoom, and a user agent | Place name |
| `https://nominatim.openstreetmap.org/search` | A bounding box around the coordinates and an amenity type | Fallback for EV, gas, or restrooms if Overpass does not answer. The website and the app wait at least 1.1 seconds between these calls. |
| `https://overpass-api.de/api/interpreter` | An Overpass query containing the coordinates | EV, gas, restrooms, and parking lots |
| `https://overpass.kumi.systems/api/interpreter` | Same query, only if the previous mirror fails | Same |
| `https://maps.mail.ru/osm/tools/overpass/api/interpreter` | Same query, only if earlier mirrors fail | Same. This host is a public Overpass mirror also used by the website. |
| `https://overpass.private.coffee/api/interpreter` | Same query, only if earlier mirrors fail | Same |
| `https://developer.nlr.gov/api/alt-fuel-stations/v1/nearest.json` | Coordinates, radius, fuel type, and `api_key` | U.S. DOE alternative-fuel stations (the same endpoint the website calls). The committed key is the public demo key `DEMO_KEY`, not a private credential. It is rate limited. Replace it before a public release and do not commit the replacement. |
| `https://api.open-meteo.com/v1/forecast` | Coordinates and which weather fields to return | Weather used for the on-device caution lines |

The iPhone app sends `User-Agent: StopAndShoot-iOS/0.1.0 (https://github.com/ejrosa/stop-and-shoot)` because Nominatim requires an identifying agent. The website lets the browser send its own user agent. The iPhone session is ephemeral: responses and cookies are not written to a disk cache by the app.

Sun times and the caution sentences are calculated on the device from the saved coordinates, the clock, and any weather already stored. Opening Apple Maps does not happen until you tap Navigate, Open in Maps, or Share.

| Action | Website | iPhone app |
| --- | --- | --- |
| Navigate / open in maps | Apple Maps on iOS, Google Maps otherwise. The share button always builds a Google Maps URL. | Apple Maps only (`https://maps.apple.com/`). The iPhone app does not call Google. |
| Share or copy | You choose the destination. The text includes coordinates. | Same, with an Apple Maps link in the text. |
| Siri confirmation | The website cannot speak through Siri. A Shortcut opens `?mark=1` in the browser. | Siri speaks a sentence with the time and accuracy, not the coordinates. |

The iPhone app does not enrich every saved spot just because it launched. It looks up a spot when you mark it or open it, and it retries spots whose lookup failed when the network returns. Turning lookups off skips those calls. Spots already fetched keep the result that was stored.

## What a spot record contains

`id`, `ts` (milliseconds), `lat`, `lon`, `acc` (meters, if known), `name`, `tags`, `note`, `parking`, and optional `place`, `weather`, and `nearby`. The iPhone app also stores `fixTs`, the GPS sample time in milliseconds. The website keeps that field if you import an iPhone JSON file and later export it again. The website's own marks leave `fixTs` empty and use `ts` as the save time.

Accuracy over 100 meters is saved and flagged. A negative accuracy is an invalid Core Location fix and is not saved.

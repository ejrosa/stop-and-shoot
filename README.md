# Stop & Shoot (working name)

Mark photo and travel spots while on the road. Two clients share a pin format and do not share a spot list:

- **Website (PWA).** Install from the browser. Spots stay in that browser's storage under `sas.pins.v1`. This is the deployed app.
- **iPhone project.** Native app in `ios/`. It is not submitted to the App Store. See [ios/README.md](ios/README.md).

Saved spots stay on the device. Place, weather, and nearby lookups send that spot's coordinates to OpenStreetMap, the U.S. DOE alternative-fuel directory, and Open-Meteo. Details: [ios/DATA_FLOW.md](ios/DATA_FLOW.md).

Rename the website with `python3 rename.py "New Name"`, then bump `CACHE` in `sw.js`. That script does not rename the iPhone project.

Checks that do not need a Mac: `bash ios/Scripts/check.sh`

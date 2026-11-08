#!/usr/bin/env python3
"""Static checks for the website and the iPhone project. No network and no Xcode."""
import json
import plistlib
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "ios"
# Names and ids from the removed sample pin. Coordinates are intentionally not repeated here.
FORBIDDEN = ("first-southpointe", "South Pointe", "Summerville", "sas.seeded")
ALLOWED_HTTP = (
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd",
    "http://www.topografix.com/GPX/1/1",
)
TEXT_SUFFIXES = {
    ".js", ".md", ".swift", ".json", ".plist", ".xcprivacy", ".py", ".mjs", ".css", ".html",
    ".webmanifest", ".xcconfig", ".pbxproj", ".yml", ".yaml", ".sh", ".xcscheme",
}
failures = []


def fail(message):
    failures.append(message)


def read(path):
    return path.read_text(encoding="utf-8")


def walk_text():
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        if any(part in {".git", ".build", "node_modules"} for part in path.parts):
            continue
        if path.suffix.lower() not in TEXT_SUFFIXES and path.name not in {".gitignore"}:
            continue
        yield path, read(path)


pem_markers = ("BEGIN " + "PRIVATE KEY", "BEGIN " + "CERTIFICATE", "BEGIN " + "RSA PRIVATE KEY")
for path, text in walk_text():
    if path.resolve() == Path(__file__).resolve():
        continue
    for needle in FORBIDDEN:
        if needle in text:
            fail(f"{path.relative_to(ROOT)} still contains {needle!r}")
    if any(marker in text for marker in pem_markers):
        fail(f"{path.relative_to(ROOT)} contains key or certificate material")
    for match in re.finditer(r"api_key=([A-Za-z0-9_\-]+)", text):
        if match.group(1) not in {"DEMO_KEY", "LOCAL_KEY"}:
            fail(f"{path.relative_to(ROOT)} has an unexpected api_key")
    if re.search(r"DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}", text):
        fail(f"{path.relative_to(ROOT)} commits a development team id")

for path in ROOT.rglob("*"):
    if path.suffix.lower() in {".p12", ".cer", ".mobileprovision", ".provisionprofile", ".pem", ".p8"}:
        fail(f"secret-like file present: {path.relative_to(ROOT)}")

app_js = read(ROOT / "app.js")
if "sas.pins.v1" not in app_js:
    fail("website no longer uses sas.pins.v1")
if "Spots stay on this phone" not in app_js:
    fail("website footer does not say spots stay on the phone")
if "Data stays on this phone" in app_js:
    fail("website still says data stays on the phone")
if "localStorage.setItem" in app_js and "pins.push" in app_js.split("loadPins")[0]:
    pass
if "pins.push({" in app_js:
    fail("website still seeds a literal pin")
if 'VERSION: "1.0.1"' not in read(ROOT / "config.js"):
    fail("website version is not 1.0.1")
if 'const CACHE = "sas-shell-v4"' not in read(ROOT / "sw.js"):
    fail("service worker cache was not bumped")

hosts = json.loads(read(IOS / "Logic/Tests/StopAndShootLogicTests/Fixtures/network_hosts.json"))
endpoints = read(IOS / "Logic/Sources/StopAndShootLogic/Endpoints.swift")
data_flow = read(IOS / "DATA_FLOW.md")
for host in hosts:
    for label, text in (("app.js", app_js), ("DATA_FLOW.md", data_flow), ("Endpoints.swift", endpoints)):
        if host not in text:
            fail(f"{host} missing from {label}")
if "https://maps.apple.com/" not in endpoints or "maps.apple.com" not in data_flow:
    fail("Apple Maps is not documented")
if "google.com" in endpoints:
    fail("lookup package calls Google")
app_dir_text = "\n".join(read(path) for path in (IOS / "App").rglob("*.swift"))
if "google.com" in app_dir_text or "requestAlwaysAuthorization" in app_dir_text:
    fail("app target contains Google or Always location")
if "allowsBackgroundLocationUpdates = false" not in read(IOS / "App/LocationService.swift"):
    fail("background location is not explicitly disabled")
logic_sources = "\n".join(read(path) for path in (IOS / "Logic/Sources").rglob("*.swift"))
if "requestAlwaysAuthorization" in logic_sources:
    fail("logic sources request Always location")

info = plistlib.loads((IOS / "Support/Info.plist").read_bytes())
for key in (
    "NSLocationWhenInUseUsageDescription",
    "NSMicrophoneUsageDescription",
    "NSSpeechRecognitionUsageDescription",
    "ITSAppUsesNonExemptEncryption",
    "CFBundleDisplayName",
    "CFBundleShortVersionString",
    "CFBundleVersion",
):
    if key not in info:
        fail(f"Info.plist missing {key}")
if info.get("ITSAppUsesNonExemptEncryption") is not False:
    fail("export compliance flag is not false")
if any(key.startswith("NSLocationAlways") for key in info):
    fail("Info.plist requests Always location")
if "UIBackgroundModes" in info:
    fail("Info.plist has background modes")
if info.get("NSAppTransportSecurity", {}).get("NSAllowsArbitraryLoads"):
    fail("arbitrary HTTP loads are allowed")
schemes = info.get("CFBundleURLTypes", [{}])[0].get("CFBundleURLSchemes", [])
if schemes != ["stopandshoot"]:
    fail(f"unexpected URL schemes: {schemes}")
joined_plist = read(IOS / "Support/Info.plist")
if "NSLocationWhenInUseUsageDescription" not in joined_plist or "background" not in joined_plist.lower():
    fail("location purpose string is missing")

privacy = plistlib.loads((IOS / "App/PrivacyInfo.xcprivacy").read_bytes())
if privacy.get("NSPrivacyTracking") is not False:
    fail("privacy manifest enables tracking")
collected = {item.get("NSPrivacyCollectedDataType") for item in privacy.get("NSPrivacyCollectedDataTypes", [])}
if "NSPrivacyCollectedDataTypePreciseLocation" not in collected:
    fail("privacy manifest does not declare precise location")
reasons = []
for item in privacy.get("NSPrivacyAccessedAPITypes", []):
    if item.get("NSPrivacyAccessedAPIType") == "NSPrivacyAccessedAPICategoryUserDefaults":
        reasons = item.get("NSPrivacyAccessedAPITypeReasons", [])
if "CA92.1" not in reasons:
    fail("UserDefaults privacy reason is missing")

xcconfig = read(IOS / "Config/Provisional.xcconfig")
identity = read(IOS / "Logic/Sources/StopAndShootLogic/Identity.swift")
readme = read(IOS / "README.md")
if "PRODUCT_BUNDLE_IDENTIFIER = dev.provisional.stopandshoot" not in xcconfig:
    fail("provisional bundle id missing")
if "dev.provisional.stopandshoot" not in identity or "dev.provisional.stopandshoot" not in readme:
    fail("bundle id is not documented as provisional")
if "MARKETING_VERSION = 0.1.0" not in xcconfig or 'marketingVersion = "0.1.0"' not in identity:
    fail("marketing version drifted")
if "CURRENT_PROJECT_VERSION = 1" not in xcconfig:
    fail("build number missing")
if "NREL_API_KEY = DEMO_KEY" not in xcconfig:
    fail("NREL key default is not the public demo key")
for phrase in ("Capacitor", "While Using", "does not listen", "Hey Grok", "not submitted", "swift test"):
    if phrase not in readme:
        fail(f"ios/README.md missing {phrase!r}")

intent = read(IOS / "App/MarkSpotIntent.swift")
if "openAppWhenRun" not in intent or "true" not in intent:
    fail("Siri intent does not open the app")
if "applicationName" not in read(IOS / "App/StopAndShootShortcuts.swift"):
    fail("Siri phrases omit the app name")
if not (IOS / "StopAndShoot.xcodeproj/project.pbxproj").exists():
    fail("Xcode project missing")
if "XCLocalSwiftPackageReference" not in read(IOS / "StopAndShoot.xcodeproj/project.pbxproj"):
    fail("Xcode project does not reference the local package")

icon = IOS / "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
blob = icon.read_bytes()
if blob[:8] != b"\x89PNG\r\n\x1a\n":
    fail("app icon is not a PNG")
width, height = struct.unpack(">II", blob[16:24])
if (width, height) != (1024, 1024) or blob[25] != 2:
    fail(f"app icon must be an opaque 1024 PNG, got {width}x{height} color type {blob[25]}")

for path, text in walk_text():
    if "ios" not in path.parts:
        continue
    for match in re.finditer(r"http://[^\s\"')\\]+", text):
        if match.group(0) not in ALLOWED_HTTP:
            fail(f"{path.relative_to(ROOT)} uses {match.group(0)}")

if failures:
    print("\n".join(failures))
    sys.exit(1)
print("audit ok")

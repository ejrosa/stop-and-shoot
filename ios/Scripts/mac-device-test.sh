#!/usr/bin/env bash
# Run on the Mac that has Xcode and the attached iPhone.
# Unsigned simulator build first. A physical install runs only when this Mac
# already has a usable Apple Development identity.
# This script does not archive, export, notarize, or upload an App Store build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

DEVICE_UDID="${STOPANDSHOOT_DEVICE_UDID:-00008150-00091DE12130401C}"
RESULTS="${STOPANDSHOOT_RESULTS:-${TMPDIR:-/tmp}/stopandshoot-mac-test}"
DERIVED_SIM="$RESULTS/derived-simulator"
DERIVED_DEV="$RESULTS/derived-device"
mkdir -p "$RESULTS"
SUMMARY="$RESULTS/summary.txt"
: > "$SUMMARY"

log() { printf '%s\n' "$*" | tee -a "$SUMMARY"; }
fail() { log "ERROR $*"; exit 1; }

log "source_root=$ROOT"
log "developer_dir=$DEVELOPER_DIR"
if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  fail "xcodebuild is not at $DEVELOPER_DIR. This Mac command was not run from Linux."
fi
xcodebuild -version | tee -a "$SUMMARY"

log "STEP scheme_list"
xcodebuild -project "$ROOT/ios/StopAndShoot.xcodeproj" -list | tee -a "$SUMMARY"
grep -q "StopAndShoot" "$SUMMARY" || fail "scheme StopAndShoot is not in the project"

log "STEP logic_tests"
SWIFT_BIN="$(xcrun --find swift)"
"$SWIFT_BIN" test --package-path "$ROOT/ios/Logic"

log "STEP simulator_build_unsigned"
set +e
xcodebuild \
  -project "$ROOT/ios/StopAndShoot.xcodeproj" \
  -scheme StopAndShoot \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$DERIVED_SIM" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build
SIM_RC=$?
set -e
if [[ $SIM_RC -ne 0 ]]; then
  log "unsigned_simulator_build_failed=$SIM_RC retrying_local_adhoc_signature"
  set +e
  xcodebuild \
    -project "$ROOT/ios/StopAndShoot.xcodeproj" \
    -scheme StopAndShoot \
    -configuration Debug \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$DERIVED_SIM" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=YES \
    build
  SIM_RC=$?
  set -e
  if [[ $SIM_RC -ne 0 ]]; then
    log "simulator_build=failed"
    log "summary_file=$SUMMARY"
    exit 1
  fi
  log "simulator_build=local_adhoc_signature"
else
  log "simulator_build=unsigned"
fi

SIM_APP=""
while IFS= read -r candidate; do
  SIM_APP="$candidate"
  break
done < <(find "$DERIVED_SIM/Build/Products" -type d -name "StopAndShoot.app")
[[ -n "$SIM_APP" && -d "$SIM_APP" ]] || fail "simulator StopAndShoot.app was not produced"
log "simulator_app=$SIM_APP"
BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print:CFBundleIdentifier' "$SIM_APP/Info.plist")"
log "bundle_id=$BUNDLE"
if /usr/libexec/PlistBuddy -c 'Print:NSLocationWhenInUseUsageDescription' "$SIM_APP/Info.plist" >/dev/null; then
  log "location_purpose=present"
else
  log "location_purpose=missing"
fi

log "STEP simulator_launch"
SIM_UDID="$(python3 - "$RESULTS" <<'PY'
import json, subprocess, sys
raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], text=True)
data = json.loads(raw)
chosen = None
for runtime, devices in data.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        if not device.get("isAvailable", True):
            continue
        name = device.get("name", "")
        if "iPhone" not in name:
            continue
        chosen = device["udid"]
        if "Pro Max" in name:
            print(chosen)
            raise SystemExit
if chosen:
    print(chosen)
PY
)"
if [[ -z "${SIM_UDID:-}" ]]; then
  log "simulator_runtime=none"
  log "simulator_launch=skipped"
else
  log "simulator_udid=$SIM_UDID"
  xcrun simctl boot "$SIM_UDID" || true
  xcrun simctl bootstatus "$SIM_UDID" -b
  xcrun simctl install "$SIM_UDID" "$SIM_APP"
  set +e
  xcrun simctl launch "$SIM_UDID" "$BUNDLE" | tee -a "$SUMMARY"
  LAUNCH_RC=${PIPESTATUS[0]}
  set -e
  if [[ $LAUNCH_RC -ne 0 ]]; then
    log "simulator_launch=failed"
    log "summary_file=$SUMMARY"
    exit 1
  fi
  log "simulator_launch=ok"
  sleep 2
  xcrun simctl io "$SIM_UDID" screenshot "$RESULTS/simulator-home.png"
  log "simulator_screenshot=$RESULTS/simulator-home.png"
  log "simulator_ui=launch_and_screenshot_only"
  log "mark_button_not_tapped=saving_a_spot_is_not_part_of_this_automation"
  if command -v idb >/dev/null 2>&1; then
    set +e
    UI_COUNT="$(idb ui describe-all --udid "$SIM_UDID" | grep -c "Mark this spot" || true)"
    set -e
    log "idb_mark_button_matches=$UI_COUNT"
  else
    log "idb=not_installed"
  fi
fi

log "STEP signing_teams"
# Print team ids only. Do not print certificate subjects, emails, or key material.
TEAM_INFO="$(python3 - <<'PY'
import re, subprocess
out = subprocess.check_output(["security", "find-identity", "-v", "-p", "codesigning"], text=True, errors="replace")
dev_lines = [line for line in out.splitlines() if "Apple Development" in line]
teams = sorted(set(re.findall(r"\(([A-Z0-9]{10})\)", "\n".join(dev_lines))))
print(str(len(dev_lines)))
print(" ".join(teams))
PY
)"
DEV_COUNT="$(printf '%s\n' "$TEAM_INFO" | sed -n '1p')"
TEAM_IDS="$(printf '%s\n' "$TEAM_INFO" | sed -n '2p')"
log "apple_development_identity_count=$DEV_COUNT"
log "team_ids=${TEAM_IDS:-NONE}"

CHOSEN_TEAM="${STOPANDSHOOT_TEAM_ID:-}"
if [[ -z "$CHOSEN_TEAM" ]]; then
  TEAM_COUNT="$(printf '%s' "$TEAM_IDS" | wc -w | tr -d ' ')"
  if [[ "$TEAM_COUNT" == "1" ]]; then
    CHOSEN_TEAM="$TEAM_IDS"
  fi
fi

log "STEP device"
DEVICE_CONNECTED=no
if xcrun devicectl list devices > "$RESULTS/devicectl-devices.txt" 2>"$RESULTS/devicectl-devices.err"; then
  if grep -q "$DEVICE_UDID" "$RESULTS/devicectl-devices.txt"; then
    DEVICE_CONNECTED=yes
  fi
fi
log "device_udid_connected=$DEVICE_CONNECTED"
log "device_udid=$DEVICE_UDID"

if [[ "$DEV_COUNT" == "0" || -z "${TEAM_IDS:-}" || "$TEAM_IDS" == "NONE" ]]; then
  log "DEVICE_RESULT=skipped_no_signing_identity"
  log "summary_file=$SUMMARY"
  exit 0
fi
if [[ -z "$CHOSEN_TEAM" ]]; then
  log "DEVICE_RESULT=skipped_multiple_teams"
  log "set STOPANDSHOOT_TEAM_ID to one id from team_ids and run this script again"
  log "summary_file=$SUMMARY"
  exit 0
fi
if [[ "$DEVICE_CONNECTED" != "yes" ]]; then
  log "DEVICE_RESULT=skipped_device_not_connected"
  log "summary_file=$SUMMARY"
  exit 0
fi

log "device_team_id=$CHOSEN_TEAM"
log "device_signing=automatic_development_only"
log "app_store_upload=not_run"
set +e
xcodebuild \
  -project "$ROOT/ios/StopAndShoot.xcodeproj" \
  -scheme StopAndShoot \
  -configuration Debug \
  -destination "platform=iOS,id=$DEVICE_UDID" \
  -derivedDataPath "$DERIVED_DEV" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$CHOSEN_TEAM" \
  CODE_SIGN_STYLE=Automatic \
  build
DEV_RC=$?
set -e
if [[ $DEV_RC -ne 0 ]]; then
  log "DEVICE_RESULT=build_failed"
  log "summary_file=$SUMMARY"
  exit 1
fi

DEV_APP=""
while IFS= read -r candidate; do
  DEV_APP="$candidate"
  break
done < <(find "$DERIVED_DEV/Build/Products" -type d -name "StopAndShoot.app")
[[ -n "$DEV_APP" && -d "$DEV_APP" ]] || fail "device StopAndShoot.app was not produced"
DEV_BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print:CFBundleIdentifier' "$DEV_APP/Info.plist")"
log "device_app=$DEV_APP"
log "device_bundle_id=$DEV_BUNDLE"
set +e
xcrun devicectl device install app --device "$DEVICE_UDID" "$DEV_APP"
INSTALL_RC=$?
if [[ $INSTALL_RC -eq 0 ]]; then
  xcrun devicectl device process launch --device "$DEVICE_UDID" "$DEV_BUNDLE"
  LAUNCH_RC=$?
else
  LAUNCH_RC=1
fi
set -e
if [[ $INSTALL_RC -ne 0 || $LAUNCH_RC -ne 0 ]]; then
  log "DEVICE_RESULT=install_or_launch_failed"
  log "summary_file=$SUMMARY"
  exit 1
fi
log "DEVICE_RESULT=launched"
log "device_ui=process_launched_mark_was_not_tapped"
log "summary_file=$SUMMARY"
exit 0

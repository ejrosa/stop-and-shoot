#!/usr/bin/env bash
# Runs the checks that do not need a Mac, Xcode, or a phone.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
python3 tests/audit_repo.py
node --check app.js
node tests/sun_parity.mjs
if ! command -v swift >/dev/null 2>&1; then
  if [[ -x "${HOME}/swift/usr/bin/swift" ]]; then
    export PATH="${HOME}/swift/usr/bin:${PATH}"
  fi
fi
swift test --package-path ios/Logic

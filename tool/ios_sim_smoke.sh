#!/usr/bin/env bash
# Installs a simulator build on the newest iPhone and iPad simulators, starts
# it, and saves a screenshot and the app's log for each. Fails if the app is
# no longer running after starting up (a crash on launch). Needs macOS with
# Xcode; the iOS workflow (.github/workflows/ios.yml) runs it.
#
#   bash tool/ios_sim_smoke.sh build/ios/iphonesimulator/Runner.app build/ios_screens
set -euo pipefail

APP=${1:-build/ios/iphonesimulator/Runner.app}
OUT=${2:-build/ios_screens}
BUNDLE=com.personal.jingyaopaint
mkdir -p "$OUT"

# The newest iOS runtime, and the newest iPhone and iPad Pro it supports.
read -r RUNTIME PHONE TABLET < <(xcrun simctl list runtimes -j | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"]
            if r.get("platform") == "iOS" and r.get("isAvailable")]
newest = max(runtimes, key=lambda r: [int(p) for p in r["version"].split(".")])
types = newest["supportedDeviceTypes"]
phone = [t for t in types if t["name"].startswith("iPhone") and "SE" not in t["name"]][-1]
tablet = [t for t in types if t["name"].startswith("iPad Pro")][-1]
print(newest["identifier"], phone["identifier"], tablet["identifier"])
')
echo "Runtime: $RUNTIME"

failed=0
for kind in phone tablet; do
  type=$([ "$kind" = phone ] && echo "$PHONE" || echo "$TABLET")
  udid=$(xcrun simctl create "JingyaoPaint-$kind" "$type" "$RUNTIME")
  echo "== $kind: $type ($udid)"
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl install "$udid" "$APP"
  xcrun simctl launch "$udid" "$BUNDLE"
  # Debug builds compile Dart on first start; give it time to draw.
  sleep 30
  xcrun simctl io "$udid" screenshot "$OUT/$kind.png"
  xcrun simctl spawn "$udid" log show --last 2m \
    --predicate 'process == "Runner"' > "$OUT/$kind.log" 2>&1 || true
  if xcrun simctl spawn "$udid" launchctl list | grep -q "$BUNDLE"; then
    echo "$kind: running"
  else
    echo "::error::$kind: the app is not running (crashed on launch?). See $kind.log."
    failed=1
  fi
  xcrun simctl shutdown "$udid" || true
done
exit $failed

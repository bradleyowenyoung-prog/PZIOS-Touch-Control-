#!/bin/bash
# sign-app.sh <pziOS.app> <identity or - for ad hoc> [entitlements.plist]
# Signs everything inside the app, innermost first, then the helper and the app with their entitlements.
# Entitlements: the third argument for the app if given; else, when the bundle contains embedded.mobileprovision and a real identity is used, the usable ones from that
# profile (application-identifier, team, get-task-allow, increased memory limit); else the ones already in the app, else HostApp/pziOS.entitlements.
# get-task-allow is always added for ad-hoc signing (the built-in JIT attaches a debugger). Sideloading tools replace all of this with the user's own signature.
set -e
APP=${1:?app}; ID=${2:--}; GIVEN=${3:-}; ROOT=$(cd "$(dirname "$0")/.." && pwd)
SIGN="/usr/bin/codesign -f -s $ID --timestamp=none"

ents_for() {      # $1 bundle dir, $2 explicit plist or empty -> prints the path of an entitlements plist
  local B=$1 G=$2 OUT; OUT=$(mktemp)
  if [ -n "$G" ]; then cp "$G" "$OUT"
  elif [ "$ID" != "-" ] && [ -f "$B/embedded.mobileprovision" ]; then
    security cms -D -i "$B/embedded.mobileprovision" 2>/dev/null | python3 -c '
import sys, plistlib
e = plistlib.loads(sys.stdin.buffer.read()).get("Entitlements", {})
keep = ["application-identifier", "com.apple.developer.team-identifier", "get-task-allow", "com.apple.developer.kernel.increased-memory-limit"]
sys.stdout.buffer.write(plistlib.dumps({k: e[k] for k in keep if k in e}))' > "$OUT"
  else
    /usr/bin/codesign -d --entitlements - --xml "$B" > "$OUT" 2>/dev/null || true
    [ -s "$OUT" ] || { [ "$B" = "$APP" ] && cp "$ROOT/HostApp/pziOS.entitlements" "$OUT"; } || true
    [ -s "$OUT" ] || printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict/></plist>' > "$OUT"
    if [ "$ID" = "-" ]; then
      /usr/libexec/PlistBuddy -c "Add :get-task-allow bool true" "$OUT" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :get-task-allow true" "$OUT"
    fi
  fi
  echo "$OUT"
}

find "$APP" -type f \( -name '*.dylib' -o -name java -o -name jspawnhelper \) -print0 | xargs -0 -n 16 $SIGN
for f in "$APP"/Frameworks/*.framework "$APP"/Frameworks/*.xcframework "$APP"/PlugIns/*/Frameworks/*.framework; do [ -e "$f" ] && $SIGN "$f"; done
for x in "$APP"/PlugIns/*.appex; do
  [ -e "$x" ] || continue
  E=$(ents_for "$x" ""); $SIGN --entitlements "$E" "$x"; rm -f "$E"
done
E=$(ents_for "$APP" "$GIVEN"); $SIGN --entitlements "$E" "$APP"; rm -f "$E"
/usr/bin/codesign --verify --deep --strict "$APP" && echo "signed ($ID)"

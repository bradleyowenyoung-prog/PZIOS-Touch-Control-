#!/bin/bash
# Sign every Mach-O under the bundled JRE with the build identity (nested code is not signed by Xcode).
set -e
[ -n "$EXPANDED_CODE_SIGN_IDENTITY" ] || exit 0      # unsigned build (scripts/make-ipa.sh signs afterwards)
JRE="$CODESIGNING_FOLDER_PATH/runtime/jre"; NAT="$CODESIGNING_FOLDER_PATH/runtime/natives"
[ -d "$JRE" ] || exit 0
find "$JRE" "$NAT" -type f \( -name '*.dylib' -o -name java -o -name jspawnhelper \) -print0 |
  xargs -0 -n 16 /usr/bin/codesign -f -s "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none

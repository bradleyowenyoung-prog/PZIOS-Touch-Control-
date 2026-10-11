#!/bin/bash
# retag.sh <in.dylib> <out.dylib>: thin to arm64, rewrite platform macOS -> iOS (min 17.0), and flatten macOS
# versioned framework paths (X.framework/Versions/A/X -> X.framework/X). Signing happens in the Xcode build phase.
set -e
T=$(mktemp -d); lipo "$1" -thin arm64 -output "$T/thin" 2>/dev/null || cp "$1" "$T/thin"
vtool -arch arm64 -set-build-version ios 17.0 27.0 -replace -output "$T/tagged" "$T/thin" 2>/dev/null
cp "$T/tagged" "$2"
otool -L "$2" | tail -n +2 | awk '{print $1}' | grep -E '^/System/Library/Frameworks/[^/]+\.framework/Versions/' | while read dep; do
  new=$(echo "$dep" | sed -E 's#(/System/Library/Frameworks/([^/]+)\.framework)/Versions/[^/]+/.*#\1/\2#')
  install_name_tool -change "$dep" "$new" "$2" 2>/dev/null
done
rm -rf "$T"

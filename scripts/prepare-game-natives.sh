#!/bin/bash
# prepare-game-natives.sh "<Project Zomboid.app or its Contents folder>" <output dir>
# Turns the macOS native libraries that ship with YOUR copy of the game into iOS libraries pziOS can load. Nothing from the game is kept in this repository;
# run this on your own machine, then drop the output into HostApp/runtime/natives (or let inject-game-natives.sh add it to a built IPA).
#   - 9 libraries come from Contents/Java (FMOD, the PZ engine libraries, RakNet, imgui, assimp)
#   - 5 more come out of Contents/Java/projectzomboid.jar (LWJGL, jemalloc, sqlite)
# libfmod and libfmodstudio also have their macOS-only imports redirected (Carbon, AudioUnit, CoreAudio) to the iOS shims built by native/build-natives.sh.
set -e
GAME=${1:?path to Project Zomboid.app (or its Contents folder)}; OUT=${2:?output folder}
[ -d "$GAME/Contents" ] && GAME="$GAME/Contents"
JAVA="$GAME/Java"; [ -f "$JAVA/projectzomboid.jar" ] || { echo "projectzomboid.jar not found under $JAVA"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; mkdir -p "$OUT"
( cd "$T" && unzip -q -o "$JAVA/projectzomboid.jar" 'macos/arm64/org/lwjgl/*' 'org/sqlite/native/Mac/aarch64/*' )
retag() { "$HERE/retag.sh" "$1" "$OUT/$(basename "$1")"; }
for l in libfmod libfmodstudio libfmodintegration libimgui-java64 libjassimp libLighting libPZBullet libPZClipper libPZPathFind libPZPopMan libRakNet libZNetNoSteam; do
  retag "$JAVA/$l.dylib"
done
retag "$T/macos/arm64/org/lwjgl/liblwjgl.dylib"
retag "$T/macos/arm64/org/lwjgl/opengl/liblwjgl_opengl.dylib"
retag "$T/macos/arm64/org/lwjgl/stb/liblwjgl_stb.dylib"
retag "$T/macos/arm64/org/lwjgl/jemalloc/libjemalloc.dylib"
retag "$T/org/sqlite/native/Mac/aarch64/libsqlitejdbc.dylib"
# macOS-only imports -> the audio shims (libfmodhal*, built from native/fmodhal) or harmless system libraries
M=/System/Library/Frameworks
install_name_tool -change $M/Carbon.framework/Carbon /usr/lib/libresolv.9.dylib \
                  -change $M/AudioUnit.framework/AudioUnit @rpath/libfmodhal.dylib \
                  -change $M/CoreAudio.framework/CoreAudio @rpath/libfmodhal_ca.dylib "$OUT/libfmod.dylib"
install_name_tool -change $M/AudioUnit.framework/AudioUnit $M/AudioToolbox.framework/AudioToolbox \
                  -change $M/Carbon.framework/Carbon /usr/lib/libresolv.9.dylib \
                  -change $M/CoreAudio.framework/CoreAudio /usr/lib/libz.1.dylib "$OUT/libfmodstudio.dylib"
# the FMOD libraries find each other (and the audio shims) next to themselves
for l in libfmod libfmodstudio libfmodintegration; do install_name_tool -add_rpath @loader_path "$OUT/$l.dylib"; done
# manifest: hashes of the ORIGINAL macOS libraries, so the app can tell when the game it imports has newer ones than the ones converted here
python3 - "$JAVA" "$T" "$OUT/native_manifest.json" <<'PY'
import hashlib, json, sys, os
java, tmp, out = sys.argv[1:4]
sha = lambda p: hashlib.sha256(open(p, "rb").read()).hexdigest()
javalibs = "libfmod libfmodstudio libfmodintegration libimgui-java64 libjassimp libLighting libPZBullet libPZClipper libPZPathFind libPZPopMan libRakNet libZNetNoSteam".split()
jarlibs = ["macos/arm64/org/lwjgl/liblwjgl.dylib", "macos/arm64/org/lwjgl/opengl/liblwjgl_opengl.dylib", "macos/arm64/org/lwjgl/stb/liblwjgl_stb.dylib",
           "macos/arm64/org/lwjgl/jemalloc/libjemalloc.dylib", "org/sqlite/native/Mac/aarch64/libsqlitejdbc.dylib"]
json.dump({"java": {l + ".dylib": sha(f"{java}/{l}.dylib") for l in javalibs}, "jar": {j: sha(f"{tmp}/{j}") for j in jarlibs}}, open(out, "w"), indent=1)
PY
echo "prepared $(ls "$OUT" | wc -l) files in $OUT"

#!/bin/bash
# Builds the native iOS libraries pziOS loads next to the JVM: libglfw (own GLFW implementation), libEGLproxy (sits between gl4es and MetalANGLE), libGLshim (GL entry points, ES-level shader fixes,
# ASTC texture compression) and libfmodhal (audio shim for the game's macOS FMOD). Output goes to HostApp/runtime/natives (or $OUT).
# Needs: Xcode with the iOS SDK, a checkout of ARM's astc-encoder (ASTC_SRC) and the gl4es dylib you built (see docs/BUILDING.md).
set -e
cd "$(dirname "$0")"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
CC="xcrun --sdk iphoneos clang -arch arm64 -isysroot $SDK -miphoneos-version-min=17.0"
OUT=${OUT:-../HostApp/runtime/natives}
ASTC_SRC=${ASTC_SRC:?set ASTC_SRC to the astc-encoder checkout (its Source/ folder)}
GL4ES_DYLIB=${GL4ES_DYLIB:-$OUT/libgl4es_114.dylib}
FRAMEWORKS=${FRAMEWORKS:-../HostApp/Frameworks}      # holds MetalANGLE.framework
mkdir -p "$OUT" .obj

echo "libglfw"
$CC -dynamiclib -fobjc-arc -O2 -install_name @rpath/libglfw.dylib glfw-ios/glfw_ios.m \
  -framework UIKit -framework Foundation -framework QuartzCore -framework Metal -framework CoreGraphics -framework ImageIO -framework GameController \
  -o "$OUT/libglfw.dylib"

echo "libEGLproxy (gl4es links to it; it re-exports MetalANGLE)"
$CC -dynamiclib -O2 -install_name @rpath/libEGLproxy.dylib eglproxy/eglproxy.c -F "$FRAMEWORKS" -Wl,-reexport_framework,MetalANGLE -o "$OUT/libEGLproxy.dylib"

echo "libfmodhal"
$CC -dynamiclib -O2 -install_name @rpath/libfmodhal.dylib fmodhal/fmodhal.c -framework AudioToolbox -framework CoreFoundation -o "$OUT/libfmodhal.dylib"
$CC -dynamiclib -O2 -install_name @rpath/libfmodhal_ca.dylib fmodhal/fmodhal.c -framework AudioToolbox -framework CoreFoundation -o "$OUT/libfmodhal_ca.dylib"      # same code; libfmod imports it under a second name for CoreAudio

echo "astc-encoder + wrapper"
for f in "$ASTC_SRC"/Source/astcenc_*.cpp; do
  o=.obj/$(basename "${f%.cpp}").o
  [ "$o" -nt "$f" ] || $CC -c -O3 -std=c++14 -DASTCENC_NEON=1 -DASTCENC_SSE=0 -DASTCENC_AVX=0 -DASTCENC_POPCNT=0 -DASTCENC_F16C=0 -I"$ASTC_SRC/Source" "$f" -o "$o"
done
$CC -c -O3 -std=c++14 -I"$ASTC_SRC/Source" astc/astc_wrap.cpp -o .obj/astc_wrap.o

echo "libGLshim"
$CC -dynamiclib -fobjc-arc -O2 -Wno-unused-function -framework Foundation -lc++ -install_name @rpath/libGLshim.dylib -Wl,-rpath,@loader_path \
  "$GL4ES_DYLIB" glshim/glshim.m .obj/*.o -o "$OUT/libGLshim.dylib"
ls -la "$OUT/libglfw.dylib" "$OUT/libfmodhal.dylib" "$OUT/libGLshim.dylib"

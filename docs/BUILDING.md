# Building

This is the order things are built in. Several steps depend on files from **your own copy** of Project Zomboid (Mac version) which cannot be shared.
Steps marked *(reconstructed)* were written from the maintainer's working notes and have not been replayed from scratch; open an issue if one fails.

## 0. Requirements

- Mac with Xcode (iOS 27 SDK used so far), `xcodegen`, `lipo`, `vtool`, `install_name_tool`.
- An iPhone or iPad with Developer Mode on. TXM devices (A17/M4 and newer) need the debugger-based JIT path.
- The game: Project Zomboid Build 42.21 for Mac (any copy of `Project Zomboid.app`).

## 1. The JVM (OpenJDK 25 for iOS)

The JRE shipped in releases is built from the upstream tag `jdk-25.0.1+8` plus the full source change set `openjdk-25.0.1+8-pzios-source.patch.gz` (attached to every release; it applies cleanly with `git apply` on that tag). It contains the iOS port (from Baconium/iOS-JVM-s), our TXM sandbox fix (`patches/4_txm_sandbox.diff`) and the ZGC address-space probe and diagnostics (`patches/5_*.diff`, `6_*.diff`). The steps below show the path without the full patch.

1. Check out https://github.com/Baconium/iOS-JVM-s and apply `patches/baconium-scripts-build.sh.diff` (build script paths).
2. Copy `patches/4_txm_sandbox.diff` next to the other iOS patches and build JDK 25 with its scripts. The result is a JRE folder (`bin/java`, `lib/`).
3. Place it at `HostApp/runtime/jre`. The Xcode build phase `sign_jre.sh` signs every Mach-O in it.

## 2. Graphics: gl4es and MetalANGLE

1. Build gl4es (commit `ec16bed`, no changes) for iOS arm64 as `libgl4es_114.dylib`. *(reconstructed: CMake with the iOS toolchain, GLES2 backend)*
2. Get `MetalANGLE.framework` for iOS (it ships inside PojavLauncher iOS builds, or build it from the MetalANGLE repository) into `HostApp/Frameworks/`.

## 3. Our native libraries

```
ASTC_SRC=/path/to/astc-encoder GL4ES_DYLIB=/path/to/libgl4es_114.dylib native/build-natives.sh
```

This builds `libglfw`, `libEGLproxy`, `libfmodhal` (twice, as `libfmodhal_ca` too) and `libGLshim` into `HostApp/runtime/natives/`.

## 4. The game's own native libraries

Run `scripts/retag.sh <in.dylib> <out.dylib>` on every `.dylib` in the game's `Contents/Java` (and the lwjgl/FMOD libraries it ships), writing the results into `HostApp/runtime/natives/`.
The libraries include FMOD, RakNet, jemalloc, the PZ pathfinding and bullet libraries and others. They are Mac builds; retagging marks them as iOS and flattens framework paths.

## 5. StikJIT

Get `StikJIT.xcframework` from the StikJIT project (https://github.com/StikDebug/StikJIT, MPL-2.0; see its integration guide) and place it at `HostApp/Frameworks/StikJIT.xcframework`. The JIT helper app extension links it on device builds only. (StikDebug, the app, is not needed unless you use the manual JIT script.)

## 6. The app

```
cd HostApp && xcodegen generate
open ZomIOS.xcodeproj      # scheme ZomIOS (device) or ZomUIPreview (simulator, launcher UI only)
```

Set your own team and bundle identifier in `project.yml`. Install, then use the in-app Setup guide for the game files and JIT.

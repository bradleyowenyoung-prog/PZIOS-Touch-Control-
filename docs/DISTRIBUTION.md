# Releases and signing

## Release IPA

`pziOS-<version>-b42.21.ipa` is built with `scripts/make-ipa.sh` and then `scripts/inject-game-natives.sh` using the maintainer's copy of Build 42.21. It contains the app, OpenJDK for iOS, our translation layers, gl4es, MetalANGLE, the JIT helper and the game's iOS-converted native libraries. It does **not** contain game assets (`projectzomboid.jar`, `media/`, sounds, textures) or any personal file (pairing file, certificate, provisioning profile, device list).

This project is free, non-commercial, and not for distribution on app stores.

## Variant without the game's libraries

`pziOS-<version>-no-game-libs.ipa` is the same IPA without the 17 game libraries, for people who use a different game build. Add yours with `scripts/inject-game-natives.sh` (see README).

## What must stay out of the repository and the IPA

- `projectzomboid.jar`, `media/`, and every other game asset.
- Your pairing file, certificates, provisioning profiles, device lists.
- The PZ_Optimization classes unless its author has given permission.
- Binaries do not go into the git repository; releases are attached to GitHub releases.

## What to include for the open-source parts

- OpenJDK is GPLv2 with the Classpath Exception: every release that ships the JRE must also offer the corresponding source: attach `openjdk-25.0.1+8-pzios-source.patch.gz` (upstream tag `jdk-25.0.1+8` + our changes) to the release (see `THIRD_PARTY.md`).
- MetalANGLE (BSD), gl4es (MIT), astc-encoder (Apache-2.0): keep their licence texts with the binaries (add them to the IPA's resources).
- StikJIT (MPL-2.0): keep `licenses/StikJIT-MPL-2.0.txt` and publish any changes made to its files.

## Signing

`make-ipa.sh` signs ad hoc with the entitlements embedded (increased memory limit, `get-task-allow` for the debugger-based JIT). Sideloading tools replace the signature with the user's own.

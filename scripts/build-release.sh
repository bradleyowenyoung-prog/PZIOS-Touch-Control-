#!/bin/bash
# build-release.sh "<Project Zomboid.app>" [output folder]
# Builds both release IPAs from release.config: <name>-no-game-libs.ipa and <name>.ipa (the same with the game's libraries of YOUR game copy added).
# Prerequisites: see docs/BUILDING.md (JRE, MetalANGLE, StikJIT, our natives). Edit release.config first (bundle id, team, name, signing).
set -e
GAME=${1:?path to Project Zomboid.app}; ROOT=$(cd "$(dirname "$0")/.." && pwd); OUT=${2:-$ROOT/release}; mkdir -p "$OUT"
[ -f "${RELEASE_CONFIG:-$ROOT/release.config}" ] && . "${RELEASE_CONFIG:-$ROOT/release.config}"
"$ROOT/scripts/make-ipa.sh" "$OUT/pziOS-no-game-libs.ipa"
"$ROOT/scripts/inject-game-natives.sh" "$OUT/pziOS-no-game-libs.ipa" "$GAME" "$OUT/pziOS.ipa" "${SIGN_IDENTITY:--}"
ls -la "$OUT"/*.ipa

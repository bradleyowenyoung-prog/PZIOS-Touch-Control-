#!/bin/bash
# update-game-libs.sh "<Project Zomboid.app>" [pziOS.ipa] [signing identity]
# After a Project Zomboid update, rebuilds your pziOS IPA with the new game's libraries (the app warns when they differ). Writes "<name>-updated.ipa" next to the
# original; sideload that one (it replaces the installed app and keeps your game files and saves). Needs the pziOS repository's scripts folder.
set -e
GAME=${1:?path to Project Zomboid.app}; HERE=$(cd "$(dirname "$0")" && pwd)
IPA=${2:-$(ls -t pziOS*.ipa 2>/dev/null | head -1)}; [ -n "$IPA" ] && [ -f "$IPA" ] || { echo "pass the path of your pziOS IPA as the second argument"; exit 1; }
OUT="${IPA%.ipa}-updated.ipa"
"$HERE/inject-game-natives.sh" "$IPA" "$GAME" "$OUT" "${3:--}"
echo "Next: sideload $OUT (Sideloadly / AltStore), then open pziOS. Your game files and saves are kept."

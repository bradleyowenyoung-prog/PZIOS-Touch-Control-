#!/bin/bash
# inject-game-natives.sh <pziOS.ipa> "<Project Zomboid.app>" <out.ipa> [signing identity]
# Adds the iOS-converted libraries of YOUR game copy to a pziOS IPA and signs it (ad hoc by default; pass an identity to sign with your own certificate).
# Sideloading tools (Sideloadly, AltStore) re-sign the IPA with your Apple ID afterwards. The result contains copyrighted game libraries: keep it to yourself.
set -e
IPA=${1:?ipa}; GAME=${2:?game app}; OUT=${3:?output ipa}; ID=${4:--}; HERE=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
unzip -q "$IPA" -d "$T"
APP=$(ls -d "$T"/Payload/*.app); NAT="$APP/runtime/natives"; mkdir -p "$NAT"
"$HERE/prepare-game-natives.sh" "$GAME" "$NAT"
"$HERE/sign-app.sh" "$APP" "$ID"
( cd "$T" && rm -f "$OUT" && zip -qry "$OUT" Payload )
echo "wrote $OUT"

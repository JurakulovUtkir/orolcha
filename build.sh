#!/bin/bash
# Orolcha'ni yig'ish:  ./build.sh          → build/Orolcha.app (Apple Silicon + Intel)
#                      ./build.sh install  → ~/Applications/Orolcha.app ga o'rnatib ishga tushiradi
# Faqat joriy arxitektura uchun tezroq yig'ish:  ARCHS=arm64 ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Orolcha.app
SDK=$(xcrun --show-sdk-path)
ARCHS=${ARCHS:-"arm64 x86_64"}

rm -rf "$APP" build/bin
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/bin

bins=()
clang_archs=()
for a in $ARCHS; do
  swiftc -swift-version 5 -O -whole-module-optimization \
    -target "$a-apple-macos14.0" -sdk "$SDK" -parse-as-library \
    Sources/*.swift -o "build/bin/Orolcha-$a"
  bins+=("build/bin/Orolcha-$a")
  clang_archs+=(-arch "$a")
done
lipo -create "${bins[@]}" -output "$APP/Contents/MacOS/Orolcha"

clang -dynamiclib -fobjc-arc -O2 "${clang_archs[@]}" -mmacosx-version-min=14.0 \
  -framework Foundation -o "$APP/Contents/Resources/MediaBridge.dylib" Helper/MediaBridge.m

cp Helper/media-bridge.pl "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/"

codesign --force --sign - "$APP/Contents/Resources/MediaBridge.dylib"
codesign --force --sign - --identifier uz.orolcha.app "$APP"

echo "Tayyor: $APP ($ARCHS)"

if [[ "${1:-}" == "install" ]]; then
  pkill -x Orolcha 2>/dev/null && sleep 1 || true
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Orolcha.app"
  cp -R "$APP" "$HOME/Applications/"
  open "$HOME/Applications/Orolcha.app"
  echo "O'rnatildi va ishga tushdi: ~/Applications/Orolcha.app"
fi

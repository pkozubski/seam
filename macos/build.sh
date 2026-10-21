#!/bin/bash
# Buduje Seam.app bez Xcode (wystarczą Command Line Tools).
#   ./build.sh                       → build/Seam.app (release, arch hosta)
#   CONFIG=debug ./build.sh          → bez optymalizacji
#   ARCH=x86_64 ./build.sh           → inna architektura
#   UNIVERSAL=1 ./build.sh           → arm64 + x86_64 (lipo)
#   VERSION=1.2.3 BUILD_NUMBER=42 ./build.sh
#   UPDATE_CHANNEL=dev ./build.sh   → automatyczne aktualizacje testowe
#   APP_OUTPUT=/tmp/seam-preview.app ./build.sh → osobny bundle do kontroli UI
#   SIGN_IDENTITY="Seam Dev" ./build.sh   → stały certyfikat (trwałe uprawnienia TCC)
#   bez SIGN_IDENTITY: certyfikat „Apple Development” z pęku kluczy, a gdy go nie ma – ad-hoc
set -euo pipefail
cd "$(dirname "$0")"

ARCH="${ARCH:-$(uname -m)}"
CONFIG="${CONFIG:-release}"
if [ -z "${SIGN_IDENTITY:-}" ] && [ "${REQUIRE_STABLE_SIGNING:-0}" != "1" ]; then
  # Lokalnie: stały certyfikat Apple Development (jeśli jest w pęku kluczy) sprawia,
  # że zgody TCC (Dostępność, nagrywanie ekranu i dźwięku) przetrwają przebudowanie.
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development:/ { print $2; exit }')"
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [ "${REQUIRE_STABLE_SIGNING:-0}" = "1" ] && [ "$SIGN_IDENTITY" = "-" ]; then
  echo "✗ Wydanie wymaga stałego certyfikatu; podpis ad-hoc zerwałby uprawnienia macOS." >&2
  exit 1
fi
VERSION="${VERSION:-$(cat ../VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
UPDATE_CHANNEL="${UPDATE_CHANNEL:-stable}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Nieprawidłowy VERSION: $VERSION" >&2; exit 1; }
case "$UPDATE_CHANNEL" in stable|dev) ;; *) echo "Nieprawidłowy UPDATE_CHANNEL" >&2; exit 1;; esac
DEPLOY="14.2"
# Stały identyfikator sprzed zmiany nazwy: od niego zależą zgody TCC, ustawienia i Pęk kluczy.
BUNDLE_ID="com.borderlessmouse.mac"
OUT="${APP_OUTPUT:-build/Seam.app}"

# SDK decyduje o wyglądzie: binarka zlinkowana z SDK macOS 26 dostaje na Tahoe nowy
# wygląd systemu (szklane kontrolki), starsze SDK dają tryb kompatybilności.
# Dlatego wybieramy najnowszy SDK spośród Command Line Tools i wszystkich Xcode, ale tylko
# taki, który obecny swiftc potrafi wczytać (obraz CI bywa z SDK nowszym niż kompilator).
sdk_works() {
  local probe
  probe="$(mktemp -d)"
  echo 'print(0)' > "$probe/probe.swift"
  swiftc -typecheck -sdk "$1" "$probe/probe.swift" >/dev/null 2>&1
  local status=$?
  rm -rf "$probe"
  return $status
}
pick_sdk() {
  local best="" best_ver="0" sdk ver
  while IFS=$'\t' read -r ver sdk; do
    [ -n "$sdk" ] || continue
    if sdk_works "$sdk"; then best="$sdk"; best_ver="$ver"; break; fi
    echo "→ pomijam SDK $ver – swiftc go nie obsługuje" >&2
  done < <(
    for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX[0-9]*.sdk \
               /Applications/Xcode*.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX[0-9]*.sdk; do
      [ -d "$sdk" ] || continue
      printf '%s\t%s\n' "$(basename "$sdk" | sed -E 's/MacOSX([0-9.]+)\.sdk/\1/')" "$sdk"
    done | sort -t$'\t' -k1,1 -rV
  )
  if [ -z "$best" ]; then best="$(xcrun --sdk macosx --show-sdk-path)"; best_ver="$(xcrun --sdk macosx --show-sdk-version)"; fi
  SDK="$best"; SDK_VERSION="$best_ver"
}
pick_sdk
echo "→ SDK macOS $SDK_VERSION ($SDK)"
if [ -n "${REQUIRE_SDK_MAJOR:-}" ] && [ "${SDK_VERSION%%.*}" -lt "$REQUIRE_SDK_MAJOR" ]; then
  echo "✗ Wymagany SDK macOS ${REQUIRE_SDK_MAJOR}+, znaleziono ${SDK_VERSION}. Zainstaluj nowsze Xcode/Command Line Tools." >&2
  exit 1
fi

OPT="-O"
[ "$CONFIG" = "debug" ] && OPT="-Onone -g"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" build/obj

SOURCES=$(find Seam/Sources -name '*.swift' | sort)
# Pomocnik aplikacji Windows (osobna ikona w Docku dla każdej aplikacji Windows): mały program
# kopiowany do wygenerowanych pakietów, więc tylko pliki, których potrzebuje.
HOST_SOURCES="SeamHost/SeamHost.swift
Seam/Sources/Display/WinHostLink.swift
Seam/Sources/Display/WinWindowProxies.swift
Seam/Sources/Display/H264Decompressor.swift
Seam/Sources/Protocol/Protocol.swift
Seam/Sources/Protocol/ClipboardContent.swift
Seam/Sources/Protocol/VideoStream.swift
Seam/Sources/Security/PairingSecurity.swift
Seam/Sources/Localization/L10n.swift"

compile() { # $1 = arch, $2 = output
  echo "→ swiftc ($CONFIG, $1)"
  swiftc $OPT -swift-version 5 -parse-as-library -module-name Seam \
    -target "$1-apple-macos${DEPLOY}" -sdk "$SDK" \
    -framework SwiftUI -framework AppKit -framework Network \
    -framework CoreAudio -framework AudioToolbox -framework CryptoKit \
    -framework ServiceManagement -framework Security \
    -framework ScreenCaptureKit -framework VideoToolbox -framework CoreMedia -framework CoreVideo \
    -import-objc-header Seam/Sources/Display/CGVirtualDisplay.h \
    -o "$2" $SOURCES
}

compile_host() { # $1 = arch, $2 = output
  echo "→ swiftc SeamHost ($CONFIG, $1)"
  swiftc $OPT -swift-version 5 -parse-as-library -module-name SeamHost \
    -target "$1-apple-macos${DEPLOY}" -sdk "$SDK" \
    -framework AppKit -framework CryptoKit -framework Security \
    -framework VideoToolbox -framework CoreMedia -framework CoreVideo \
    -o "$2" $HOST_SOURCES
}

mkdir -p "$OUT/Contents/Helpers"
if [ "${UNIVERSAL:-0}" = "1" ]; then
  compile arm64 build/obj/Seam-arm64
  compile x86_64 build/obj/Seam-x86_64
  lipo -create build/obj/Seam-arm64 build/obj/Seam-x86_64 \
       -output "$OUT/Contents/MacOS/Seam"
  compile_host arm64 build/obj/SeamHost-arm64
  compile_host x86_64 build/obj/SeamHost-x86_64
  lipo -create build/obj/SeamHost-arm64 build/obj/SeamHost-x86_64 \
       -output "$OUT/Contents/Helpers/SeamHost"
else
  compile "$ARCH" "$OUT/Contents/MacOS/Seam"
  compile_host "$ARCH" "$OUT/Contents/Helpers/SeamHost"
fi

sed -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/g" \
    -e 's/\$(EXECUTABLE_NAME)/Seam/g' \
    -e 's/\$(PRODUCT_NAME)/Seam/g' \
    -e "s/\$(MARKETING_VERSION)/$VERSION/g" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD_NUMBER/g" \
    -e "s/\$(UPDATE_CHANNEL)/$UPDATE_CHANNEL/g" \
    -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/$DEPLOY/g" \
    Seam/Info.plist > "$OUT/Contents/Info.plist"
printf 'APPL????' > "$OUT/Contents/PkgInfo"
cp Seam/Resources/AppIcon.icns Seam/Resources/Seam.entitlements "$OUT/Contents/Resources/"
# Updater wersji sprzed zmiany nazwy podpisuje nowy bundle plikiem o dawnej nazwie.
cp Seam/Resources/Seam.entitlements "$OUT/Contents/Resources/BorderlessMouse.entitlements"
cp Seam/Resources/ReleaseSigning.cer "$OUT/Contents/Resources/"
cp ../assets/seam/*.png "$OUT/Contents/Resources/"
cp ../THIRD_PARTY_NOTICES.md "$OUT/Contents/Resources/THIRD_PARTY_NOTICES.txt"
for localization in Seam/Resources/*.lproj; do
  [ -d "$localization" ] && cp -R "$localization" "$OUT/Contents/Resources/"
done

echo "→ codesign ($SIGN_IDENTITY)"
SIGN_ARGS=(--force --sign "$SIGN_IDENTITY" --options runtime --entitlements Seam/Seam.entitlements)
if [ -n "${SIGN_KEYCHAIN:-}" ]; then SIGN_ARGS+=(--keychain "$SIGN_KEYCHAIN"); fi
if [ "${REQUIRE_STABLE_SIGNING:-0}" = "1" ]; then
  CERT_HASH=$(/usr/bin/openssl x509 -inform DER -in Seam/Resources/ReleaseSigning.cer -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
  SIGN_ARGS+=(--requirements "=designated => identifier \"$BUNDLE_ID\" and anchor H\"$CERT_HASH\"")
  SIGN_ARGS+=(--timestamp)
fi
# Zagnieżdżony program najpierw (podpis pakietu obejmuje jego podpis); bez uprawnień Seam.
HOST_SIGN_ARGS=(--force --sign "$SIGN_IDENTITY" --options runtime)
if [ -n "${SIGN_KEYCHAIN:-}" ]; then HOST_SIGN_ARGS+=(--keychain "$SIGN_KEYCHAIN"); fi
if [ "${REQUIRE_STABLE_SIGNING:-0}" = "1" ]; then HOST_SIGN_ARGS+=(--timestamp); fi
codesign "${HOST_SIGN_ARGS[@]}" "$OUT/Contents/Helpers/SeamHost"
codesign "${SIGN_ARGS[@]}" "$OUT"
codesign --verify --strict --deep --all-architectures "$OUT"
if [ "${REQUIRE_STABLE_SIGNING:-0}" = "1" ]; then
  codesign --verify --strict --all-architectures \
    -R "=identifier \"$BUNDLE_ID\" and anchor H\"$CERT_HASH\"" "$OUT"
fi
echo "✓ $OUT (v$VERSION build $BUILD_NUMBER, kanał $UPDATE_CHANNEL, SDK $SDK_VERSION)"

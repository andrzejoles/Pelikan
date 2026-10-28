#!/usr/bin/env bash
# Instalatory macOS (Apple Silicon, jak w Bifoldzie): dist/Pelikan-X.Y.Z.dmg (przeciągnij do Aplikacji)
# i dist/Pelikan-X.Y.Z.pkg (kreator instalacji do /Applications). Podpisana kopia: dist/staging.noindex/Pelikan-X.Y.Z.app
# (katalog .noindex — Spotlight i Launchpad nie pokazują jej jako kolejnej aplikacji).
# Podpis: stały certyfikat z własnym podpisem (scripts/signing.sh) — zgody macOS (Pęk kluczy) zostają po aktualizacjach.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(scripts/version.sh)"
BUILD="$(scripts/version.sh --build)"
DIST="$ROOT/dist"
APP_NAME="$(awk -F' = ' '/^PELIKAN_APP_NAME/{print $2}' Config/Brand.xcconfig)"
REPO="$(awk -F' = ' '/^PELIKAN_REPOSITORY/{print $2}' Config/Brand.xcconfig)"
echo "=== $APP_NAME $VERSION ($BUILD) ==="

echo "[1/4] Budowanie (Release)…"
scripts/set-version.sh
# Mapa prefiksów: kod C zależności (np. BoringSSL w __FILE__) wpisuje do binarki ścieżki budowania — z katalogiem
# domowym budującego. Ustawienia z wiersza poleceń obejmują też cele pakietów SPM. Dla Swifta bez mapy
# (-file-prefix-map psuje jawne moduły Xcode), a kod Swift ścieżek nie zostawia — pilnuje tego sprawdzenie niżej.
# Bez dSYM: po mapie prefiksów dsymutil nie znajduje modułów .pcm (dziesiątki ostrzeżeń), a symbole i tak usuwa strip.
xcodebuild -project Pelikan.xcodeproj -scheme Pelikan -destination 'platform=macOS,arch=arm64' -configuration Release -derivedDataPath build/DerivedData.noindex \
    -skipPackagePluginValidation -skipMacroValidation \
    OTHER_CFLAGS="\$(inherited) -ffile-prefix-map=$ROOT=." DEBUG_INFORMATION_FORMAT=dwarf \
    build -quiet
SRC="build/DerivedData.noindex/Build/Products/Release/$APP_NAME.app"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SRC/Contents/Info.plist")" = "$VERSION" ] \
    || { echo "BŁĄD: wersja w Info.plist nie zgadza się z $VERSION" >&2; exit 1; }

echo "[2/4] Podpis…"
mkdir -p "$DIST"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
APP="$DIST/staging.noindex/$APP_NAME-$VERSION.app"
rm -rf "$DIST/staging.noindex"
mkdir -p "$DIST/staging.noindex"
ditto "$SRC" "$APP"
# Dane dewelopera i bazy testowej nie mogą trafić do instalatora.
LEAKED="$(find "$APP" \( -name "connections.json" -o -name "settings.json" -o -name "history.json" -o -name "*.p12" \
    -o -name "*.pem" -o -name "tnsnames.ora" -o -name "cwallet.sso" -o -name "env" -o -name "id_ed25519*" -o -name "libclntsh*" \) -print)"
[ -z "$LEAKED" ] || { echo "BŁĄD: w pakiecie są pliki z danymi: $LEAKED" >&2; exit 1; }
# Symbole debugowania (tablica STABS z ścieżkami plików .o i źródeł) zostają w kompilacji Release bez instalacji — usuwamy
# je z naszych plików wykonywalnych przed podpisem (Sparkle ma już własny, podpisany i ostrzyżony).
find "$APP/Contents/MacOS" "$APP/Contents/PlugIns" -type f -perm -u+x -print0 | while IFS= read -r -d '' f; do
    if [[ "$(file -b "$f")" == *Mach-O* ]]; then strip -S -x "$f" 2>/dev/null; fi
done
# Ani ścieżek budowania, ani katalogu domowego w plikach wykonywalnych i zasobach.
PATHS="$(grep -rlF -e "$ROOT" -e "$HOME/" "$APP" || true)"
[ -z "$PATHS" ] || { echo "BŁĄD: pliki w pakiecie zawierają ścieżki z katalogu domowego: $PATHS" >&2; exit 1; }
scripts/third-party-licenses.sh "$APP/Contents/Resources/Licencje zewnętrzne.txt"
scripts/signing.sh sign "$APP"

echo "[3/4] PKG…"
PKG="$DIST/$APP_NAME-$VERSION.pkg"
PKGROOT="$(mktemp -d)"
trap 'rm -rf "$PKGROOT"' EXIT
ditto "$APP" "$PKGROOT/root/$APP_NAME.app"
pkgbuild --analyze --root "$PKGROOT/root" "$PKGROOT/component.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$PKGROOT/component.plist"
# Bez sprawdzania wersji: instalator nie pomija aplikacji o „niższym” numerze (1.0.0 po betach 10.x, D184).
plutil -replace 0.BundleIsVersionChecked -bool NO "$PKGROOT/component.plist"
pkgbuild --root "$PKGROOT/root" --component-plist "$PKGROOT/component.plist" --install-location /Applications \
    --identifier "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist").pkg" \
    --version "$VERSION" "$PKG" >/dev/null

echo "[4/4] DMG…"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
STAGE="$PKGROOT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Aplikacje (Applications)"
cp "$APP/Contents/Resources/Licencje zewnętrzne.txt" "$STAGE/"
cp LICENSE "$STAGE/LICENSE.txt"
cat > "$STAGE/Instrukcja instalacji.txt" <<TXT
$APP_NAME $VERSION — natywne IDE dla Oracle PL/SQL na macOS (Apple Silicon, macOS 27)
Autor: Andrzej Oleś w kooperacji z Claude AI · licencja MIT · https://github.com/$REPO

INSTALACJA
1. Przeciągnij „${APP_NAME}” na „Aplikacje (Applications)”.
2. Pierwsze uruchomienie: aplikacja nie jest notaryzowana przez Apple, więc macOS ją zablokuje.
   Otwórz Ustawienia systemowe → Prywatność i ochrona → „Otwórz mimo to”.
   (W Terminalu: xattr -dr com.apple.quarantine /Applications/$APP_NAME.app)

ORACLE INSTANT CLIENT (sterownik domyślny)
  Licencja Oracle nie pozwala dołączyć go do aplikacji — pobierz „Instant Client for macOS (ARM64)”, pakiet Basic
  albo Basic Light, ze strony Oracle (https://www.oracle.com/database/technologies/instant-client/macos-arm64-downloads.html).
  Pelikan znajduje go w Homebrew, /opt/oracle/instantclient* i w Pobranych; inny katalog: Ustawienia › Oracle.
  Bez Instant Client działa sterownik „thin” (wybór w definicji połączenia) — z ograniczeniami (bez TCPS/wallet,
  Kerberos i przerwania wykonania).

AKTUALIZACJE
  Aplikacja raz dziennie sprawdza nowe wydania (menu $APP_NAME → Sprawdź uaktualnienia…).
  Każde wydanie jest podpisane kluczem autora (EdDSA) — aplikacja nie przyjmie pliku z innego źródła.
TXT
hdiutil create -quiet -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

"$LSREGISTER" -u "$ROOT/$SRC" 2>/dev/null || true
"$LSREGISTER" -u "$APP" 2>/dev/null || true

echo "Gotowe:"
ls -lh "$DMG" "$PKG"
shasum -a 256 "$DMG" "$PKG"

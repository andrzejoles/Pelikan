#!/usr/bin/env bash
# Wydanie: instalatory, archiwum dla Sparkle, appcast.xml podpisany kluczem EdDSA i SZKIC wydania na GitHubie
# (jak w Bifoldzie). Publikacja po sprawdzeniu szkicu: gh release edit vX.Y.Z --draft=false.
# Zainstalowane kopie pobiorą aktualizację same dopiero po publikacji (kanał: releases/latest/download/appcast.xml).
# Bez --beta (od 1.0.0, D184): notatki z sekcji „## <wersja>” w docs/NOWOSCI.md, jeśli jest.
# --beta: tytuł „… beta” i notatki z docs/BETA.md. Celowo NIE „pre-release” na GitHubie: kanał Sparkle to
# releases/latest, a GitHub pomija wydania wstępne w „latest” — testerzy nie dostaliby kolejnych wersji (D153).
set -euo pipefail
BETA=0
[ "${1:-}" = "--beta" ] && BETA=1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "Wydanie tylko z gałęzi main" >&2; exit 1; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "Najpierw zatwierdź zmiany" >&2; exit 1; }
git fetch -q origin main
[ "$(git rev-parse origin/main)" = "$(git rev-parse HEAD)" ] || { echo "Najpierw zsynchronizuj main z GitHubem (git pull / git push)" >&2; exit 1; }

VERSION="$(scripts/version.sh)"
TAG="v$VERSION"
REPO="$(awk -F' = ' '/^PELIKAN_REPOSITORY/{print $2}' Config/Brand.xcconfig)"
APP_NAME="$(awk -F' = ' '/^PELIKAN_APP_NAME/{print $2}' Config/Brand.xcconfig)"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || gh release view "$TAG" >/dev/null 2>&1; then
    echo "Wydanie $TAG już istnieje" >&2
    exit 1
fi

scripts/build-installer.sh

RELEASE_DIR="$ROOT/dist/staging.noindex/release-$VERSION"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
# Archiwum dla Sparkle: tylko ono w katalogu, bo generate_appcast czyta wszystkie archiwa.
ditto "dist/staging.noindex/$APP_NAME-$VERSION.app" "$RELEASE_DIR/stage/$APP_NAME.app"
ditto -c -k --sequesterRsrc --keepParent "$RELEASE_DIR/stage/$APP_NAME.app" "$RELEASE_DIR/$APP_NAME-$VERSION.zip"
rm -rf "$RELEASE_DIR/stage"
scripts/sparkle-tools.sh generate_appcast \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    --link "https://github.com/$REPO/releases/tag/$TAG" \
    "$RELEASE_DIR"

PREVIOUS="$(git describe --tags --abbrev=0 2>/dev/null || true)"
TITLE="$APP_NAME $VERSION"
# Nowości z docs/NOWOSCI.md: sekcja „## <wersja>” bez nagłówka i sekcje wersji pośrednich bez osobnego wydania (nowsze niż
# poprzedni znacznik) jako „### Także z <wersja> — opis”.
NEWS="$(python3 - "$VERSION" "${PREVIOUS#v}" docs/NOWOSCI.md <<'PY' 2>/dev/null
import re, sys
version, previous, path = sys.argv[1], sys.argv[2], sys.argv[3]
key = lambda v: tuple(int(x) for x in v.split("."))
sections = re.split(r"(?m)^## ", open(path, encoding="utf-8").read())[1:]
out = []
for s in sections:
    head, _, body = s.partition("\n")
    m = re.match(r"(\d+\.\d+\.\d+)(.*)", head)
    if not m:
        continue
    v = m.group(1)
    # Poprzedni znacznik „wyższy” od bieżącej wersji (bety 10.x przed 1.0.0) nie ogranicza listy.
    bounded = re.fullmatch(r"\d+\.\d+\.\d+", previous or "") and key(previous) < key(version)
    if key(v) > key(version) or (bounded and key(v) <= key(previous)):
        continue
    out.append(body.strip() if v == version else "### Także z " + head.strip() + "\n\n" + body.strip())
print("\n\n".join(out))
PY
)"
[ "$BETA" = 1 ] && TITLE="$TITLE beta"
{
    echo "$TITLE"
    echo
    if [ "$BETA" = 1 ]; then
        sed -e '1d' -e '/^Autor: /d' docs/BETA.md
        echo
        echo "## Zmiany od poprzedniego wydania"
        echo
    elif [ -n "$NEWS" ]; then
        printf '%s\n' "$NEWS"
        echo
        echo "## Zmiany od poprzedniego wydania"
        echo
    fi
    # Zmiany wchodzą na main przez scalenia PR: tytuł PR jest w treści commita scalającego.
    git log --first-parent --format='%s%n%b' ${PREVIOUS:+"$PREVIOUS..HEAD"} \
        | awk '/^Merge pull request #[0-9]+ from /{n=$4; next} n!="" && NF{print "- " $0 " (" n ")"; n=""}' | head -40 || true
    cat <<NOTES

## Instalacja (macOS 27, Apple Silicon)
Pobierz \`$APP_NAME-$VERSION.dmg\` i przeciągnij aplikację do Aplikacji (albo uruchom \`$APP_NAME-$VERSION.pkg\`).
Aplikacja nie jest notaryzowana: przy pierwszym uruchomieniu Ustawienia systemowe → Prywatność i ochrona → „Otwórz mimo to”.
Oracle Instant Client (sterownik domyślny) instalujesz sam ze strony Oracle — szczegóły w „Instrukcja instalacji.txt” w DMG.
Bez niego działa sterownik thin (wybór w definicji połączenia). Zainstalowane kopie aktualizują się same.

Pliki \`$APP_NAME-$VERSION.zip\` i \`appcast.xml\` służą automatycznym aktualizacjom.

Autor: Andrzej Oleś w kooperacji z Claude AI · licencja MIT
NOTES
} > "$RELEASE_DIR/notes.md"

git tag "$TAG"
git push origin "$TAG"
# Nieudane utworzenie wydania (sieć, uprawnienia, plik) nie może zostawić samego tagu — ponowne uruchomienie
# odmówiłoby wtedy („już istnieje”), a tag trzeba by usuwać ręcznie lokalnie i na GitHubie.
if ! gh release create "$TAG" --draft --title "$TITLE" --notes-file "$RELEASE_DIR/notes.md" \
    "$RELEASE_DIR/$APP_NAME-$VERSION.zip" "$RELEASE_DIR/appcast.xml" "dist/$APP_NAME-$VERSION.dmg" "dist/$APP_NAME-$VERSION.pkg"; then
    echo "Nie udało się utworzyć wydania $TAG — usuwam tag (lokalnie i na GitHubie)" >&2
    gh release delete "$TAG" --yes >/dev/null 2>&1 || true   # częściowo utworzony szkic
    git push -q origin ":refs/tags/$TAG" || true
    git tag -d "$TAG" >/dev/null
    exit 1
fi
echo "Szkic wydania $TAG gotowy. Sprawdź go na GitHubie i opublikuj: gh release edit $TAG --draft=false"

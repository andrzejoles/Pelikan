#!/usr/bin/env bash
# Stały podpis aplikacji certyfikatem z własnym podpisem („Pelikan Self-Signed”).
#
# Po co: podpis ad-hoc zmienia się przy każdej kompilacji, a macOS wiąże z podpisem Pełny dostęp do
# dysku i dostęp do haseł w Pęku kluczy — po każdej aktualizacji trzeba by je nadawać od nowa.
# Z tym certyfikatem wymaganie podpisu to „identyfikator + certyfikat”, więc nadane zgody zostają.
# To nie zastępuje Developer ID: Gatekeeper i tak pokaże ostrzeżenie przy pierwszym uruchomieniu.
#
# Certyfikat i klucz prywatny są w osobnym pęku kluczy ~/Library/Keychains/pelikan-signing.keychain-db
# (hasło losowe, zapisane w pęku logowania jako „pelikan-signing-keychain”). Nic z tego nie trafia do repozytorium.
#
# Użycie: scripts/signing.sh ensure            tworzy tożsamość (raz)
#         scripts/signing.sh sign Pelikan.app   podpisuje pakiet od środka
#         scripts/signing.sh export KATALOG    kopia zapasowa (pęk kluczy + jego hasło) — poza repozytorium!
#         scripts/signing.sh restore KATALOG   odtworzenie z kopii (np. na nowym Macu)
#         scripts/signing.sh import plik.p12   tożsamość z pliku .p12 (np. własny certyfikat)
set -euo pipefail
KC="$HOME/Library/Keychains/pelikan-signing.keychain-db"
NAME="Pelikan Self-Signed"
SERVICE="pelikan-signing-keychain"

password() { security find-generic-password -s "$SERVICE" -a pelikan -w 2>/dev/null; }

# Polecenie `security` z hasłem: przez stdin trybu interaktywnego, nie w argumentach procesu (widocznych w `ps`).
# `printf` jest wbudowany w powłokę, więc hasło nie trafia do argumentów żadnego procesu; kod wyjścia — z polecenia.
# Ścieżki w cudzysłowie (security -i rozdziela słowa jak powłoka); hasła są szesnastkowe albo bez znaku `"`.
sec() { printf '%s\n' "$1" | security -i; }

create_keychain() {
    local pw
    pw="$(openssl rand -hex 24)"
    sec "add-generic-password -U -s \"$SERVICE\" -a pelikan -w $pw -T /usr/bin/security"
    sec "create-keychain -p $pw \"$KC\""
    security set-keychain-settings "$KC"
    # Bez dopisywania do listy wyszukiwania użytkownika (codesign dostaje --keychain). Ścieżki jako osobne argumenty —
    # także ze spacjami (bash 3.2 z macOS: bez mapfile, pusta tablica przez ${…+…}).
    local list=() k
    while IFS= read -r k; do
        k="$(printf '%s' "$k" | sed -E 's/^[[:space:]]*"?//; s/"?[[:space:]]*$//')"
        [ -n "$k" ] && [[ "$k" != *pelikan-signing* ]] && list+=("$k")
    done < <(security list-keychains -d user)
    security list-keychains -d user -s ${list[@]+"${list[@]}"}
}

import_p12() {
    local file="$1" p12pw="$2"
    sec "unlock-keychain -p $(password) \"$KC\""
    sec "import \"$file\" -k \"$KC\" -P \"$p12pw\" -T /usr/bin/codesign" >/dev/null
    sec "set-key-partition-list -S apple-tool:,apple:,codesign: -s -k $(password) \"$KC\"" >/dev/null
}

ensure() {
    if [ ! -f "$KC" ] || [ -z "$(password)" ]; then
        [ -f "$KC" ] && { echo "Jest $KC, ale brak hasła w pęku logowania — usuń plik albo użyj import" >&2; exit 1; }
        create_keychain
        local tmp p12pw
        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' RETURN
        p12pw="$(openssl rand -hex 16)"
        cat > "$tmp/cert.cnf" <<CNF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
O=Pelikan
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF
        openssl req -x509 -newkey rsa:3072 -nodes -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -days 7300 -config "$tmp/cert.cnf" 2>/dev/null
        openssl pkcs12 -export -legacy -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" -passout fd:3 3<<<"$p12pw" 2>/dev/null \
            || openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" -passout fd:3 3<<<"$p12pw"
        import_p12 "$tmp/id.p12" "$p12pw"
        echo "Utworzono tożsamość „${NAME}” w $KC" >&2
    fi
    sec "unlock-keychain -p $(password) \"$KC\""
}

identity() {
    security find-identity -p codesigning "$KC" | awk -v n="\"$NAME\"" 'index($0, n) {print $2; exit}'
}

# Hardened Runtime jawnie (`--options runtime`) dla każdej części — `flags` w --preserve-metadata zachowałoby go tylko,
# gdyby był już w dotychczasowym podpisie; uprawnienia (np. disable-library-validation) zostają z podpisu Xcode.
sign_one() {
    codesign --force --sign "$ID" --keychain "$KC" --timestamp=none --options runtime \
        --preserve-metadata=identifier,entitlements,flags "$@"
}

case "${1:-}" in
    ensure)
        ensure
        identity
        ;;
    sign)
        APP="${2:?Podaj ścieżkę do Pelikan.app}"
        ensure
        ID="$(identity)"
        [ -n "$ID" ] || { echo "Brak tożsamości ${NAME}" >&2; exit 1; }
        # Od środka: części Sparkle, frameworki, programy pomocnicze, na końcu pakiet.
        SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
        if [ -d "$SPARKLE" ]; then
            for x in "$SPARKLE"/XPCServices/*.xpc; do [ -e "$x" ] && sign_one "$x"; done
            sign_one "$SPARKLE/Autoupdate"
            sign_one "$SPARKLE/Updater.app"
            sign_one "$APP/Contents/Frameworks/Sparkle.framework"
        fi
        for f in "$APP"/Contents/Frameworks/*.framework; do
            [ "$(basename "$f")" = "Sparkle.framework" ] || sign_one "$f"
        done
        # Rozszerzenia (Quick Look) — z uprawnieniami z dotychczasowego podpisu (build-installer.sh usuwa z nich symbole).
        for x in "$APP"/Contents/PlugIns/*.appex; do [ -e "$x" ] && sign_one "$x"; done
        for exe in "$APP"/Contents/MacOS/*; do
            [ "$(basename "$exe")" = "$(defaults read "$APP/Contents/Info" CFBundleExecutable)" ] || sign_one "$exe"
        done
        sign_one "$APP"
        codesign --verify --deep --strict "$APP"
        codesign -d --verbose=2 "$APP" 2>&1 | grep -q 'flags=.*runtime' || { echo "Brak Hardened Runtime w podpisie $APP" >&2; exit 1; }
        codesign -d -r- "$APP" 2>&1 | grep designated
        ;;
    export)
        # Kopia całego pęku (zaszyfrowany swoim hasłem) i hasła — bez eksportu klucza, który
        # wymagałby okna zgody z hasłem pęku.
        DIR="${2:?Podaj katalog kopii}"
        # 700 tylko na samym katalogu kopii (ostatnim w ścieżce) — wystarczy, pliki mają 600.
        # shellcheck disable=SC2174
        mkdir -p -m 700 "$DIR"
        ensure >/dev/null
        (umask 077
         cp -p "$KC" "$DIR/pelikan-signing.keychain-db"
         password > "$DIR/pelikan-signing-haslo-pęku.txt"
         chmod 600 "$DIR/pelikan-signing.keychain-db" "$DIR/pelikan-signing-haslo-pęku.txt")
        echo "Zapisano w $DIR — przechowuj poza repozytorium (np. menedżer haseł, zaszyfrowany dysk)."
        ;;
    restore)
        DIR="${2:?Podaj katalog kopii}"
        [ ! -f "$KC" ] || { echo "Już jest $KC — najpierw go usuń, jeśli chcesz odtworzyć kopię" >&2; exit 1; }
        PW="$(cat "$DIR/pelikan-signing-haslo-pęku.txt")"
        cp -p "$DIR/pelikan-signing.keychain-db" "$KC"
        sec "add-generic-password -U -s \"$SERVICE\" -a pelikan -w $PW -T /usr/bin/security"
        sec "unlock-keychain -p $PW \"$KC\""
        identity
        ;;
    import)
        FILE="${2:?Podaj plik .p12}"
        [ -f "$KC" ] || create_keychain
        read -r -s -p "Hasło do pliku $FILE: " P12PW; echo
        import_p12 "$FILE" "$P12PW"
        identity
        ;;
    *)
        echo "Użycie: $0 ensure | sign Pelikan.app | export KATALOG | restore KATALOG | import plik.p12" >&2
        exit 2
        ;;
esac

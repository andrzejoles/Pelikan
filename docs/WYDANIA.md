# Wydania i aktualizacje

Układ przeniesiony z Bifolda (PROMPT §10): stały podpis własnym certyfikatem, instalatory DMG i PKG, Sparkle z kluczem
EdDSA w Pęku kluczy, szkic wydania na GitHubie na koniec każdego etapu (publikuje właściciel).

## Wersja

Numer wersji nie jest nigdzie zapisany ręcznie (`scripts/version.sh`, test: `scripts/version-test.sh`, D184).
Od 1.0.0 (scalenie PR #102) numer jest semantyczny i liczony z tytułów scalonych PR: `feat…` → środkowa cyfra
(ostatnia od 0), `typ!:` albo tytuł od `BREAKING CHANGE:` → główna (tylko na wyraźne słowo właściciela), pozostałe →
ostatnia.
Bety sprzed 1.0.0 miały regułę `1 + PR/10 . PR mod 10 . commity od ostatniego scalonego PR` (7.9.0–10.5.0). Numer
kompilacji (`CFBundleVersion`) = liczba wszystkich commitów — rośnie z każdym wydaniem (także przy przejściu z 10.5.0
na 1.0.0), a po nim porównuje wersje Sparkle; instalator `.pkg` nie sprawdza wersji aplikacji (`BundleIsVersionChecked`
wyłączone), więc 1.0.0 zastępuje bety. Zmiany wchodzą na `main` przez PR scalane „Merge pull request” (nie squash).
`make version` wypisuje wersję; `scripts/set-version.sh` zapisuje ją do `build/Version.xcconfig` przed budowaniem.
Wydanie stabilne: `scripts/release.sh` (notatki z sekcji wersji w `docs/NOWOSCI.md` i sekcji wersji pośrednich bez
osobnego wydania — nowszych niż poprzedni znacznik); `--beta` — dawny tryb bety.

## Podpis

`scripts/signing.sh` — certyfikat „Pelikan Self-Signed” w `~/Library/Keychains/pelikan-signing.keychain-db` (hasło
pęku losowe, w pęku logowania jako „pelikan-signing-keychain”; tworzony przy pierwszym `make installer`). Stały podpis =
macOS nie zapomina zgód na dostęp do haseł w Pęku kluczy po aktualizacji. Bez notaryzacji i konta Apple Developer:
przy pierwszym uruchomieniu Gatekeeper ostrzega („Otwórz mimo to”).

Kopia zapasowa tożsamości (poza repozytorium!):
```sh
scripts/signing.sh export ~/Bezpieczne
scripts/signing.sh restore ~/Bezpieczne   # na nowym Macu
```

## Klucz aktualizacji (EdDSA)

Prywatny w Pęku kluczy logowania (konto `pelikan`), publiczny w `Config/Brand.xcconfig` (`PELIKAN_SPARKLE_PUBLIC_KEY`).
```sh
scripts/sparkle-tools.sh generate_keys -p                                   # klucz publiczny
scripts/sparkle-tools.sh generate_keys -x ~/Bezpieczne/pelikan-eddsa.txt    # kopia klucza prywatnego — poza repozytorium!
scripts/sparkle-tools.sh generate_keys -f ~/Bezpieczne/pelikan-eddsa.txt    # odtworzenie na nowym Macu
```
Utrata klucza prywatnego = zainstalowane kopie nie przyjmą kolejnych aktualizacji.

Aplikacja wymaga podpisanego kanału i sprawdza podpis archiwum przed rozpakowaniem (`SURequireSignedFeed`,
`SUVerifyUpdateBeforeExtraction` w `App/Info.plist`). `generate_appcast` podpisuje `appcast.xml` sam, bo archiwum ma
`SURequireSignedFeed` (komentarz `sparkle-signatures` na końcu pliku). Nie edytować `appcast.xml` ręcznie — zmiana
unieważnia podpis i zainstalowane kopie odrzucą kanał.

## Instalatory i szkic wydania

```sh
make installer        # dist/Pelikan-X.Y.Z.dmg i .pkg (Release, licencje zewnętrzne, podpis, kontrola danych w pakiecie)
make draft-release    # z gałęzi main: instalatory, zip i appcast.xml dla Sparkle, tag vX.Y.Z, SZKIC wydania na GitHubie
make beta-release     # jak wyżej, tytuł „… beta” i notatki z docs/BETA.md (zwykłe wydanie, nie „pre-release” — D153)
gh release edit vX.Y.Z --draft=false   # publikacja — tylko właściciel
```
Kanał aktualizacji: `https://github.com/andrzejoles/Pelikan/releases/latest/download/appcast.xml` — zainstalowane kopie
pobiorą wydanie dopiero po jego publikacji. W kompilacji Debug aktualizator jest wyłączony.

Instant Client nie trafia do instalatora (licencja Oracle — D7); `build-installer.sh` przerywa budowanie, jeśli w
pakiecie znajdzie `libclntsh*`, pliki danych aplikacji (`connections.json`, `settings.json`, `history.json`), wallet,
`tnsnames.ora` albo klucze.

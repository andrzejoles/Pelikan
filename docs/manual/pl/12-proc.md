# Pro*C: zdalny build przez SSH

Pelikan pozwala edytować programy Pro*C lokalnie i budować je na serwerze (np. AIX) przez SSH, w przepływie opartym na
Gicie: zmiany trafiają na serwer przez `git pull` w kopii roboczej (working copy) na serwerze, a Pelikan uruchamia tam
`make`, instaluje binarki i prowadzi historię wdrożeń z możliwością wycofania. Pelikan nigdy nie wysyła źródeł na
serwer bezpośrednio, nie robi na serwerze `merge` ani `reset` i nie wykonuje `git push`.

Komendy są w menu **Narzędzia › Zdalny build Pro*C**.

## Cele SSH

**Narzędzia › Zdalny build Pro*C › Cele SSH…** otwiera menedżer celów — serwerów, na które wdrażasz. Cele możesz
grupować w folderach, duplikować i usuwać. Formularz celu:

- **Połączenie**: nazwa, folder, środowisko **UAT** albo **PROD** (z kolorem), host, port, użytkownik i
  uwierzytelnianie — **Plik klucza** (opcjonalnie z hasłem klucza), **Agent SSH** albo **Hasło SSH**. Hasło SSH i
  hasło klucza zapisujesz w Pęku kluczy (**Zapamiętaj w Pęku kluczy**); przy włączonej ochronie Touch ID
  (**Ustawienia › Oracle › Hasła połączeń**) Pelikan potwierdza ich użycie raz na cel. **Stare algorytmy (AIX 6.1 i
  starsze serwery)** włącza algorytmy SSH obsługiwane przez stare serwery. **Kodowanie nazw** i **Kodowanie konsoli**
  (UTF-8 albo ISO-8859-2) ustawiają, jak Pelikan koduje nazwy plików i czyta wyjście.
- **Katalogi na serwerze**: katalog bazowy, katalog kopii zapasowych, kopia robocza oraz podkatalogi źródeł i binarek.
- **Git i build**: gałąź, remote, komenda builda (np. `make`) i lista binarek (po przecinku).
- **Środowisko powłoki**: ścieżka do `ksh`, `ORACLE_HOME`, `LIBPATH`, `PATH` i dodatkowe zmienne (`NAZWA=wartość`) —
  nieinteraktywna powłoka nie czyta `.profile`, więc tu podajesz to, czego potrzebuje build.

Definicje celów są zapisywane bez sekretów; **Eksportuj cele SSH…** i **Importuj cele SSH…** przenoszą je między
komputerami. Na serwerze nie są potrzebne żadne hasła Oracle — Pro*C ma być skonfigurowany na serwerze.

### Testowanie celu

**Testuj** (w menedżerze albo **Narzędzia › Zdalny build Pro*C › Testuj cel SSH**) sprawdza: wersję serwera SSH,
logowanie, system (`uname -a`, na AIX `oslevel -s`), dostępność `make`, `git` i `compress`/`gzip`, gałąź i czystość
kopii roboczej (`git status --porcelain`) oraz możliwość zapisu w katalogach. Brakujący katalog kopii zapasowych Pelikan utworzy
po Twoim potwierdzeniu.

Przy pierwszym teście nowego serwera Pelikan pokazuje odcisk jego klucza (SHA256) i zapisuje klucz w known_hosts
dopiero po Twoim potwierdzeniu — porównaj odcisk z podanym przez administratora. Wdrożenie na serwer, którego klucza
nie potwierdzono, jest odrzucane; serwer ze zmienionym kluczem — zawsze.

## Wdrożenie

1. Otwórz projekt z lokalnym repozytorium Git (Pelikan porówna je z serwerem). Bez projektu wdrożenie działa, ale bez
   informacji o lokalnych commitach.
2. Wybierz **Narzędzia › Zdalny build Pro*C › Wdróż na cel…** i cel. Okno pokaże **Podsumowanie**: commit na serwerze
   i w remote, commity do wdrożenia, `git diff --stat` i ostrzeżenia — np. niewypchnięte lokalne commity albo
   wdrożenie na PROD commita, którego nie było na UAT.
3. Przy celu **PROD** musisz wpisać nazwę celu, żeby potwierdzić wdrożenie.
4. Kliknij **Wdróż**.

Na serwerze Pelikan wykonuje kolejno:

1. zakłada **blokadę** (na jednym celu może trwać tylko jedno wdrożenie);
2. sprawdza gałąź i czystość kopii roboczej — ręczne zmiany na serwerze zatrzymują wdrożenie przed `pull`;
3. `git pull --ff-only`;
4. kopię zapasową binarek (z datą i commitem w nazwie, spakowaną `compress` albo `gzip`, z limitem liczby kopii);
5. `make` (komenda builda);
6. instalację nowych binarek (poprzednia wersja zostaje jako `.prev`);
7. wpis do historii wdrożeń na serwerze i w Pelikanie.

## Konsola wdrożenia

**Konsola wdrożenia** pokazuje kroki z czasem i wynikiem oraz wyjście na żywo. Błędy kompilatora Pro*C (`PCC-…`, także
`PLS-…`) i kompilatora IBM XL C (`1506-…`) są klikalne — otwierają plik w lokalnym repozytorium w linii błędu. Opcja
**Tylko błędy i ostrzeżenia** filtruje wyjście, a **Zapisz log…** zapisuje je do pliku.

**Narzędzia › Zdalny build Pro*C › Zatrzymaj wdrożenie** (albo **Stop** w konsoli) przerywa build na serwerze (także
procesy uruchomione przez `make`) i zawsze zdejmuje własną blokadę. Pozostawioną blokadę innego wdrożenia zdejmiesz
ręcznie przez **Zdejmij blokadę celu…** — tylko wtedy, gdy masz pewność, że nikt teraz nie wdraża (na PROD po wpisaniu
nazwy celu).

## Wycofanie i historia

- **Wycofaj binarkę…** zamienia bieżącą binarkę z poprzednią wersją (`.prev`) albo przywraca wybraną kopię zapasową
  (rozpakowaną, z prawami bieżącej binarki).
- **Historia wdrożeń** pokazuje wdrożenia z Pelikana (z pełnym logiem) i historię zapisaną na serwerze.
- **Stan git i wdrożeń** zestawia: lokalną gałąź i niewypchnięte commity, stan remote, ostatnie wdrożenie z historii i
  commit (HEAD) na każdym serwerze. **git fetch i odśwież** pobiera stan remote bez pytań w terminalu.

## Kodowanie plików

Źródła na starszych serwerach bywają w ISO-8859-2. Pelikan wykrywa kodowanie istniejących plików i nie zmienia go po
cichu: znak, którego nie da się zapisać w kodowaniu pliku, blokuje zapis z dokładnym wskazaniem miejsca. Kodowanie
zmienisz tylko jawnie (**Plik › Kodowanie pliku…**); projekt może też narzucić kodowanie swoich plików.

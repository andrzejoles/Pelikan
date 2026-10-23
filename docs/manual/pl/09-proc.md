# Pro*C: zdalny build przez SSH

Pelikan buduje programy Pro*C na serwerze (np. AIX) przez SSH: pobiera zmiany z repozytorium Git do working copy na
serwerze, uruchamia `make`, instaluje binarki i prowadzi historię wdrożeń z możliwością wycofania.

## Cele SSH

W **Cele SSH** definiujesz serwer: host, port, użytkownik, uwierzytelnianie (klucz, agent SSH albo hasło), kodowanie,
środowisko (ORACLE_HOME, LIBPATH, PATH), katalog bazowy, katalog backupów, gałąź i komendę builda. Hasło SSH albo hasło
klucza trafia do Pęku kluczy, a definicje celów zapisują się bez sekretów. Cele oznaczasz jako UAT albo PROD.

**Testuj** sprawdza logowanie, wersję systemu i serwera SSH, dostępność `make`, `git`, `compress`/`gzip`, gałąź i
czystość working copy oraz zapisywalność katalogów.

## Wdrożenie

Wdrożenie wykonuje kolejno: blokadę (jedno wdrożenie naraz), kontrolę working copy (ręczne zmiany na serwerze
zatrzymują wdrożenie), `git pull --ff-only`, kopię zapasową binarek, `make`, instalację i wpis do historii. Pelikan
nigdy nie robi na serwerze merge ani reset. Przed wdrożeniem na PROD trzeba wpisać nazwę celu.

Konsola pokazuje kroki z czasem i wynikiem; błędy kompilatora Pro*C (`PCC-…`) i IBM XL C (`1506-…`) są klikalne i
otwierają plik w miejscu błędu. **Stop** przerywa wdrożenie i zawsze zdejmuje blokadę. **Wycofaj** przywraca poprzednie
binarki albo wybraną kopię.

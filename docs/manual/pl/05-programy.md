# Program Window i Object Browser

## Object Browser

Drzewo obiektów bieżącego schematu (albo wybranego w filtrze) z folderami według typu: tabele, widoki, pakiety, typy,
wyzwalacze, sekwencje, a na 23ai także moduły MLE i domeny. Menu kontekstowe obiektu otwiera jego źródło, pokazuje opis,
DDL, zależności, dane, pozwala skompilować obiekt albo go usunąć. Obiekty niepoprawne są oznaczone.

## Program Window

Program Window edytuje kod PL/SQL: pakiety (specyfikacja i ciało na osobnych kartach), procedury, funkcje, typy i
wyzwalacze. **Wykonaj** (F8) kompiluje kod w bazie, a błędy kompilacji pojawiają się pod edytorem — kliknięcie przenosi do
linii. Zarys kodu (Code Contents) pokazuje strukturę jednostki, a **Przejdź do deklaracji** przenosi do miejsca
deklaracji identyfikatora.

Edytor podpowiada nazwy tabel, kolumn, pakietów i ich elementów, zwija bloki, podświetla pary `BEGIN`/`END`, formatuje
kod (**Formater**) według ustawień i zapisuje historię lokalną wersji pliku. Szablony wstawiają gotowe fragmenty kodu.

## Analiza kodu

W czasie pisania Pelikan podkreśla nieznane tabele, kolumny i aliasy oraz wskazuje problemy: nieużywane zmienne, kod
po `RETURN`, `UPDATE`/`DELETE` bez `WHERE`, niejawne konwersje. **Find Usages** szuka użyć obiektu w bazie i plikach
projektu, a **Zmień nazwę** pokazuje podgląd zmian przed zastosowaniem.

## Pliki i kodowanie

Pliki zachowują swoje kodowanie (UTF-8, ISO-8859-2, Windows-1250) i zakończenia linii. Znak, którego nie da się zapisać
w kodowaniu pliku, blokuje zapis z dokładnym wskazaniem miejsca — zmiana kodowania jest możliwa tylko jawnie
(**Plik › Kodowanie pliku**).

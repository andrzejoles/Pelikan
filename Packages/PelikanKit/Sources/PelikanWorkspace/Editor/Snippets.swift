import Foundation

/// Fragment kodu z biblioteki (SC-SNIP-001): kategoria, nazwa, tekst; własne w `Snippets/snippets.json`.
public struct Snippet: Sendable, Codable, Hashable, Identifiable {
    public var category: String
    public var name: String
    public var text: String
    public var isBuiltIn = false
    public var id: String { category + "/" + name }

    public init(category: String, name: String, text: String, isBuiltIn: Bool = false) {
        self.category = category; self.name = name; self.text = text; self.isBuiltIn = isBuiltIn
    }

    enum CodingKeys: String, CodingKey { case category, name, text }
}

/// Biblioteka snippetów: wbudowane (własne teksty Pelikana) i użytkownika (zastępują wbudowane o tym samym id).
public final class SnippetLibrary: @unchecked Sendable {
    public let file: URL?
    private let lock = NSLock()
    private var user: [Snippet] = []
    /// Błąd odczytu istniejącego pliku własnych snippetów — wtedy zapis jest zablokowany, żeby pierwsza zmiana nie
    /// nadpisała pliku pustą listą.
    public private(set) var loadError: String?

    public init(directory: URL?) {
        file = directory?.appendingPathComponent("snippets.json")
        guard let f = file, FileManager.default.fileExists(atPath: f.path) else { return }
        do { user = try JSONDecoder().decode([Snippet].self, from: try Data(contentsOf: f)) } catch { loadError = error.localizedDescription }
    }

    public static let builtIn: [Snippet] = {
        func s(_ c: String, _ n: String, _ t: String) -> Snippet { Snippet(category: c, name: n, text: t, isBuiltIn: true) }
        let dates = L10n.tr("Daty"), agg = L10n.tr("Agregacje i analityka"), plsql = "PL/SQL", hints = L10n.tr("Wskazówki optymalizatora"),
            dict = L10n.tr("Słownik danych"), json = "JSON"
        return [
            s(dates, L10n.tr("Początek miesiąca"), "TRUNC(SYSDATE, 'MM')"),
            s(dates, L10n.tr("Koniec miesiąca"), "LAST_DAY(TRUNC(SYSDATE))"),
            s(dates, L10n.tr("Dzień tygodnia (ISO)"), "TO_CHAR(SYSDATE, 'D', 'NLS_DATE_LANGUAGE=AMERICAN')"),
            s(dates, L10n.tr("Różnica w dniach"), "TRUNC(data_do) - TRUNC(data_od)"),
            s(dates, L10n.tr("Znacznik czasu UTC"), "SYS_EXTRACT_UTC(SYSTIMESTAMP)"),
            s(agg, L10n.tr("Numer wiersza w grupie"), "ROW_NUMBER() OVER (PARTITION BY kolumna ORDER BY kolumna2)"),
            s(agg, L10n.tr("Suma narastająca"), "SUM(kwota) OVER (ORDER BY data ROWS UNBOUNDED PRECEDING)"),
            s(agg, L10n.tr("Lista wartości w grupie"), "LISTAGG(kolumna, ', ') WITHIN GROUP (ORDER BY kolumna)"),
            s(agg, L10n.tr("Poprzednia wartość"), "LAG(kolumna) OVER (ORDER BY data)"),
            s(agg, L10n.tr("Pierwsze n wierszy"), "FETCH FIRST 10 ROWS ONLY"),
            s(plsql, L10n.tr("Pętla po kursorze"), "FOR r IN (SELECT * FROM tabela) LOOP\n  NULL;\nEND LOOP;"),
            s(plsql, L10n.tr("Obsługa wyjątku z logiem"), "EXCEPTION\n  WHEN OTHERS THEN\n    DBMS_OUTPUT.PUT_LINE(SQLERRM || CHR(10) || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);\n    RAISE;"),
            s(plsql, L10n.tr("Masowe pobieranie"), "SELECT * BULK COLLECT INTO l_tab FROM tabela;\nFORALL i IN 1 .. l_tab.COUNT\n  INSERT INTO cel VALUES l_tab(i);"),
            s(plsql, L10n.tr("Transakcja autonomiczna"), "PRAGMA AUTONOMOUS_TRANSACTION;"),
            s(plsql, L10n.tr("Pomiar czasu"), "l_start := DBMS_UTILITY.GET_TIME;\n-- …\nDBMS_OUTPUT.PUT_LINE((DBMS_UTILITY.GET_TIME - l_start) / 100 || ' s');"),
            s(hints, L10n.tr("Równoległość"), "/*+ PARALLEL(4) */"),
            s(hints, L10n.tr("Indeks"), "/*+ INDEX(t nazwa_indeksu) */"),
            s(hints, L10n.tr("Bez scalania widoku"), "/*+ NO_MERGE */"),
            s(hints, L10n.tr("Statystyki wykonania"), "/*+ GATHER_PLAN_STATISTICS */"),
            s(dict, L10n.tr("Niepoprawne obiekty"), "SELECT object_type, object_name FROM user_objects WHERE status = 'INVALID' ORDER BY 1, 2;"),
            s(dict, L10n.tr("Kolumny tabeli"), "SELECT column_name, data_type, data_length, nullable FROM user_tab_columns WHERE table_name = 'TABELA' ORDER BY column_id;"),
            s(dict, L10n.tr("Rozmiary segmentów"), "SELECT segment_name, ROUND(SUM(bytes) / 1024 / 1024, 1) mb FROM user_segments GROUP BY segment_name ORDER BY 2 DESC;"),
            s(json, L10n.tr("Wartość z JSON"), "JSON_VALUE(dokument, '$.klucz')"),
            s(json, L10n.tr("Tabela z JSON"), "SELECT jt.* FROM tabela t, JSON_TABLE(t.dokument, '$[*]' COLUMNS (id NUMBER PATH '$.id', nazwa VARCHAR2(100) PATH '$.nazwa')) jt"),
            s(json, L10n.tr("Obiekt JSON z kolumn"), "JSON_OBJECT('id' VALUE id, 'nazwa' VALUE nazwa)"),
        ]
    }()

    /// Wszystkie snippety: użytkownika zastępują wbudowane o tym samym id, posortowane po kategorii i nazwie.
    public var all: [Snippet] {
        lock.lock(); defer { lock.unlock() }
        var byID = Dictionary(uniqueKeysWithValues: Self.builtIn.map { ($0.id, $0) })
        for s in user { byID[s.id] = s }
        return byID.values.sorted { ($0.category, $0.name) < ($1.category, $1.name) }
    }

    public var categories: [String] { Array(Set(all.map(\.category))).sorted() }

    func checkWritable() throws {
        guard let e = loadError, let f = file else { return }
        throw CommandError.notAvailable(L10n.tr("Nie można odczytać pliku \(f.lastPathComponent) (\(e)) — popraw go albo usuń; zmiany nie zostały zapisane, żeby nie utracić własnych snippetów"))
    }

    public func save(_ s: Snippet) throws {
        try checkWritable()
        lock.lock()
        user.removeAll { $0.id == s.id }
        var copy = s
        copy.isBuiltIn = false
        user.append(copy)
        let snapshot = user
        lock.unlock()
        try write(snapshot)
    }

    public func remove(id: String) throws {
        try checkWritable()
        lock.lock()
        user.removeAll { $0.id == id }
        let snapshot = user
        lock.unlock()
        try write(snapshot)
    }

    private func write(_ list: [Snippet]) throws {
        guard let f = file else { return }
        try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(list).write(to: f, options: .atomic)
    }
}

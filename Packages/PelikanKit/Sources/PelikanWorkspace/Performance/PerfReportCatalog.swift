import Foundation

/// Format wyniku raportu (D217). Kolejność `PerfReport.formats` = preferencja (ACTIVE pierwszy, gdy dostępny).
public enum ReportFormat: String, Sendable, Codable, CaseIterable, Hashable {
    case active, html, text, xml

    public var displayName: String {
        switch self {
        case .active: L10n.tr("Active (interaktywny HTML)")
        case .html: "HTML"
        case .text: L10n.tr("Tekst")
        case .xml: "XML"
        }
    }

    /// Wartość parametru `type` funkcji Oracle.
    public var oracleType: String { rawValue.uppercased() }
    public var fileExtension: String { self == .text ? "txt" : self == .xml ? "xml" : "html" }
}

/// Źródło danych o zapytaniu (D217): gdzie Oracle jeszcze je pamięta.
public enum ReportSource: String, Sendable, Codable, CaseIterable, Hashable {
    /// Pamięć kursorów (GV$SQL) — bez licencji.
    case cursorCache
    /// ASH w pamięci (GV$ACTIVE_SESSION_HISTORY) — Diagnostics Pack.
    case ashMemory
    /// Repozytorium AWR (DBA_HIST_*) — Diagnostics Pack.
    case awr
    /// Real-Time SQL Monitoring (GV$SQL_MONITOR) — Tuning Pack.
    case sqlMonitor
    /// Zapisane raporty SQL Monitor (DBA_HIST_REPORTS, 12c+) — Tuning Pack.
    case reportRepository
    /// Oba zbiory ASH (pamięć i AWR).
    case ashBoth

    public var displayName: String {
        switch self {
        case .cursorCache: L10n.tr("Pamięć kursorów (V$SQL)")
        case .ashMemory: L10n.tr("ASH w pamięci")
        case .awr: L10n.tr("AWR (historia)")
        case .sqlMonitor: L10n.tr("SQL Monitor (pamięć)")
        case .reportRepository: L10n.tr("Zapisane raporty SQL Monitor (DBA_HIST_REPORTS)")
        case .ashBoth: L10n.tr("ASH: pamięć i AWR")
        }
    }

    /// Licencja źródła.
    public var need: PerfReport.Need {
        switch self {
        case .cursorCache: .none
        case .ashMemory, .awr, .ashBoth: .diagnostics
        case .sqlMonitor, .reportRepository: .tuning
        }
    }
}

/// Parametry raportu pytane w oknie (D217); wartości domyślne z dostępności zapytania i stanu bazy.
public enum ReportParameter: String, Sendable, Codable, Hashable {
    /// Zakres migawek AWR.
    case snapshots
    /// Drugi zakres migawek (porównania).
    case snapshots2
    /// Okno czasu (początek, koniec).
    case timeWindow
    /// Wykonanie z SQL Monitor (albo zapisany raport).
    case execution
    /// Plan (PLAN_HASH_VALUE), opcjonalnie.
    case planHash
    /// Kursor potomny (CHILD_NUMBER), opcjonalnie.
    case child
    /// Format DBMS_XPLAN.
    case planFormat
    /// Zapamiętane wartości zmiennych wiązanych.
    case binds
    /// Limit czasu doradcy (sekundy).
    case timeLimit
    /// Sesja (SID, SERIAL#, instancja).
    case session
    /// Ostatnie dni (historia operacji).
    case days
    /// Tryb czasu rzeczywistego albo historyczny.
    case realtime
    /// Wszystkie instancje RAC.
    case allInstances
}

/// Raport z katalogu (D217): licencja, wersja bazy, formaty, źródła i parametry; wywołanie — `PerfReportCall`.
public struct PerfReport: Sendable, Identifiable, Hashable {
    public enum Need: Int, Sendable, Comparable, Hashable {
        case none = 0, diagnostics, tuning
        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
        public var displayName: String {
            switch self {
            case .none: L10n.tr("bez licencji pakietów")
            case .diagnostics: "Diagnostics Pack"
            case .tuning: "Tuning Pack"
            }
        }
    }

    public enum Scope: Sendable, Hashable { case sql, global }

    public let id: String
    public let title: String
    public let summary: String
    public let group: String
    public let scope: Scope
    /// Licencja niezależna od źródła (np. DBMS_SQLTUNE — Tuning); źródło może wymagać więcej.
    public let need: Need
    /// Najniższa wersja bazy (główny numer: 11, 12, 18, 19…).
    public let minMajor: Int
    public let formats: [ReportFormat]
    /// Źródła do wyboru (puste — bez wyboru źródła).
    public let sources: [ReportSource]
    public let parameters: [ReportParameter]
    /// Funkcja Oracle (opis w oknie i dokumentacji).
    public let api: String
    /// Uwaga do raportu (np. ACTIVE wymaga internetu przy oglądaniu, zadanie doradcy w bazie).
    public let note: String?

    public init(_ id: String, _ title: String, group: String, scope: Scope, need: Need, minMajor: Int = 11, formats: [ReportFormat],
                sources: [ReportSource] = [], parameters: [ReportParameter] = [], api: String, summary: String, note: String? = nil) {
        self.id = id; self.title = title; self.group = group; self.scope = scope; self.need = need; self.minMajor = minMajor
        self.formats = formats; self.sources = sources; self.parameters = parameters; self.api = api; self.summary = summary; self.note = note
    }

    /// Licencja przy danym źródle.
    public func need(for source: ReportSource?) -> Need { max(need, source?.need ?? .none) }

    public static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }
}

/// Katalog raportów Oracle Diagnostics/Tuning Pack i bliskich (materiał właściciela, D217).
public enum PerfReportCatalog {
    static let activeNote = L10n.tr("Raport ACTIVE pobiera przy oglądaniu skrypty z serwerów Oracle — wyświetla się w oknie Pelikana (wymaga internetu); bez internetu wybierz HTML, tekst albo XML.")

    public static let sqlReports: [PerfReport] = [
        PerfReport("sql.planCursor", L10n.tr("Plan z pamięci kursorów"), group: L10n.tr("Plan"), scope: .sql, need: .none, formats: [.html, .text, .xml],
                   sources: [.cursorCache], parameters: [.child, .planFormat], api: "DBMS_XPLAN.DISPLAY_CURSOR / DISPLAY_PLAN (V$SQL_PLAN_STATISTICS_ALL)",
                   summary: L10n.tr("Plan wykonania z V$SQL_PLAN z rzeczywistymi statystykami (ALLSTATS LAST) i wartościami podejrzanymi przy parsowaniu (+PEEKED_BINDS).")),
        PerfReport("sql.planAWR", L10n.tr("Plany z AWR"), group: L10n.tr("Plan"), scope: .sql, need: .none, formats: [.text],
                   sources: [.awr], parameters: [.planHash, .planFormat], api: "DBMS_XPLAN.DISPLAY_WORKLOAD_REPOSITORY / DISPLAY_AWR",
                   summary: L10n.tr("Wszystkie plany zapytania zapisane w repozytorium AWR (DBA_HIST_SQL_PLAN).")),
        PerfReport("sql.monitor", L10n.tr("SQL Monitor — wykonanie"), group: L10n.tr("Monitorowanie"), scope: .sql, need: .tuning, formats: [.active, .html, .text, .xml],
                   sources: [.sqlMonitor, .reportRepository], parameters: [.execution], api: "DBMS_SQLTUNE.REPORT_SQL_MONITOR / DBMS_AUTO_REPORT.REPORT_REPOSITORY_DETAIL",
                   summary: L10n.tr("Raport Real-Time SQL Monitoring wybranego wykonania: plan z czasem i wierszami na krok, oczekiwania, bindy."), note: activeNote),
        PerfReport("sql.monitorList", L10n.tr("SQL Monitor — lista wykonań"), group: L10n.tr("Monitorowanie"), scope: .sql, need: .tuning, formats: [.html, .text, .xml],
                   sources: [.sqlMonitor], api: "DBMS_SQLTUNE.REPORT_SQL_MONITOR_LIST",
                   summary: L10n.tr("Monitorowane wykonania zapytania z czasem, stanem i zasobami.")),
        PerfReport("sql.detail", L10n.tr("SQL Detail"), group: L10n.tr("Monitorowanie"), scope: .sql, need: .tuning, formats: [.active, .xml],
                   sources: [.ashMemory, .awr], parameters: [.timeWindow, .planHash], api: "DBMS_SQLTUNE.REPORT_SQL_DETAIL",
                   summary: L10n.tr("Aktywność, plany, statystyki i wykonania zapytania z ASH, AWR i SQL Monitor w jednym raporcie."), note: activeNote),
        PerfReport("sql.perfHub", L10n.tr("Performance Hub — SQL"), group: L10n.tr("Monitorowanie"), scope: .sql, need: .diagnostics, minMajor: 12, formats: [.active, .xml],
                   sources: [.ashMemory, .awr], parameters: [.timeWindow], api: "DBMS_PERF.REPORT_SQL",
                   summary: L10n.tr("Szczegóły zapytania w Performance Hub: aktywność, plany, monitorowane wykonania (czas rzeczywisty albo historia AWR)."), note: activeNote),
        PerfReport("sql.awr", L10n.tr("Raport AWR dla SQL"), group: L10n.tr("Historia"), scope: .sql, need: .diagnostics, formats: [.html, .text],
                   sources: [.awr], parameters: [.snapshots], api: "DBMS_WORKLOAD_REPOSITORY.AWR_SQL_REPORT_HTML / _TEXT",
                   summary: L10n.tr("Statystyki i plany zapytania między migawkami AWR (odpowiednik awrsqrpt.sql).")),
        PerfReport("sql.ash", L10n.tr("Raport ASH dla SQL"), group: L10n.tr("Historia"), scope: .sql, need: .diagnostics, formats: [.html, .text],
                   sources: [.ashMemory, .awr, .ashBoth], parameters: [.timeWindow], api: "DBMS_WORKLOAD_REPOSITORY.ASH_REPORT_HTML / _TEXT",
                   summary: L10n.tr("Raport ASH zawężony do zapytania: oczekiwania, sesje, wiersze planu w oknie czasu.")),
        PerfReport("sql.history", L10n.tr("Historia wykonań w AWR"), group: L10n.tr("Historia"), scope: .sql, need: .diagnostics, formats: [.html, .text],
                   sources: [.awr], api: "DBA_HIST_SQLSTAT",
                   summary: L10n.tr("Wykonania, czas, odczyty i plan w każdej migawce AWR — widać zmianę planu i regresję.")),
        PerfReport("sql.binds", L10n.tr("Zapamiętane wartości bindów"), group: L10n.tr("Bindy"), scope: .sql, need: .none, formats: [.html, .text],
                   sources: [.cursorCache, .awr, .sqlMonitor], api: "V$SQL_BIND_CAPTURE / DBA_HIST_SQLBIND / V$SQL_MONITOR.BINDS_XML",
                   summary: L10n.tr("Wartości zmiennych wiązanych przechwycone przez Oracle (co najwyżej co 15 min na kursor, tylko typy proste)."),
                   note: L10n.tr("Oracle przechwytuje tylko bindy w WHERE/HAVING, bez LOB, LONG i typów obiektowych.")),
        PerfReport("sql.tuning", L10n.tr("SQL Tuning Advisor"), group: L10n.tr("Doradcy"), scope: .sql, need: .tuning, formats: [.text],
                   sources: [.cursorCache, .awr], parameters: [.snapshots, .planHash, .binds, .timeLimit], api: "DBMS_SQLTUNE.CREATE_TUNING_TASK / REPORT_TUNING_TASK",
                   summary: L10n.tr("Zalecenia doradcy (profil SQL, indeksy, statystyki, przebudowa) i skrypt; z wybranym zestawem bindów — analiza tekstu z tymi wartościami."),
                   note: L10n.tr("Tworzy zadanie doradcy w bazie (usuwane po raporcie) i wykonuje zapytanie testowo w limicie czasu.")),
        PerfReport("sql.repair", L10n.tr("SQL Repair Advisor"), group: L10n.tr("Doradcy"), scope: .sql, need: .none, minMajor: 19, formats: [.text, .html, .xml],
                   sources: [.cursorCache], parameters: [.binds, .timeLimit], api: "DBMS_SQLDIAG.CREATE_DIAGNOSIS_TASK / REPORT_DIAGNOSIS_TASK",
                   summary: L10n.tr("Diagnoza problemu wydajności zapytania i proponowana poprawka (SQL patch)."),
                   note: L10n.tr("Licencja DBMS_SQLDIAG nie jest opisana w Licensing Information; zadanie diagnozy jest usuwane po raporcie.")),
    ]

    public static let globalReports: [PerfReport] = [
        PerfReport("perf.awr", L10n.tr("Raport AWR"), group: L10n.tr("AWR"), scope: .global, need: .diagnostics, formats: [.html, .text],
                   parameters: [.snapshots, .allInstances], api: "DBMS_WORKLOAD_REPOSITORY.AWR_REPORT_HTML / AWR_GLOBAL_REPORT_HTML",
                   summary: L10n.tr("Raport AWR instancji (albo wszystkich instancji RAC) między migawkami.")),
        PerfReport("perf.awrDiff", L10n.tr("Porównanie okresów AWR"), group: L10n.tr("AWR"), scope: .global, need: .diagnostics, formats: [.html, .text],
                   parameters: [.snapshots, .snapshots2, .allInstances], api: "DBMS_WORKLOAD_REPOSITORY.AWR_DIFF_REPORT_HTML",
                   summary: L10n.tr("Porównanie dwóch okresów AWR (np. dziś i tydzień temu).")),
        PerfReport("perf.addm", L10n.tr("ADDM"), group: L10n.tr("AWR"), scope: .global, need: .diagnostics, formats: [.text],
                   parameters: [.snapshots], api: "DBMS_ADDM.ANALYZE_DB / GET_REPORT",
                   summary: L10n.tr("Analiza ADDM okresu między migawkami: ustalenia i zalecenia."), note: L10n.tr("Tworzy zadanie ADDM (usuwane po raporcie).")),
        PerfReport("perf.addmCompare", L10n.tr("Porównanie okresów ADDM"), group: L10n.tr("AWR"), scope: .global, need: .diagnostics, minMajor: 12, formats: [.active, .xml],
                   parameters: [.snapshots, .snapshots2], api: "DBMS_ADDM.COMPARE_DATABASES",
                   summary: L10n.tr("Compare Period ADDM — przyczyny różnicy wydajności dwóch okresów."), note: activeNote),
        PerfReport("perf.ash", L10n.tr("Raport ASH"), group: L10n.tr("ASH"), scope: .global, need: .diagnostics, formats: [.html, .text],
                   sources: [.ashMemory, .awr, .ashBoth], parameters: [.timeWindow], api: "DBMS_WORKLOAD_REPOSITORY.ASH_REPORT_HTML",
                   summary: L10n.tr("Aktywność sesji w oknie czasu: oczekiwania, SQL, sesje, obiekty.")),
        PerfReport("perf.ashAnalytics", L10n.tr("ASH Analytics"), group: L10n.tr("ASH"), scope: .global, need: .diagnostics, minMajor: 19, formats: [.active],
                   parameters: [.timeWindow], api: "DBMS_WORKLOAD_REPOSITORY.ASH_REPORT_ANALYTICS",
                   summary: L10n.tr("Interaktywna analiza ASH z wymiarami (oczekiwania, SQL, moduły…)."), note: activeNote),
        PerfReport("perf.perfHub", L10n.tr("Performance Hub"), group: L10n.tr("Bieżąca praca"), scope: .global, need: .diagnostics, minMajor: 12, formats: [.active, .xml],
                   parameters: [.realtime, .timeWindow], api: "DBMS_PERF.REPORT_PERFHUB",
                   summary: L10n.tr("Performance Hub: aktywność, top SQL, monitorowane zapytania, ADDM — w czasie rzeczywistym albo z AWR."), note: activeNote),
        PerfReport("perf.session", L10n.tr("Raport sesji"), group: L10n.tr("Bieżąca praca"), scope: .global, need: .diagnostics, minMajor: 12, formats: [.xml],
                   parameters: [.session, .realtime, .timeWindow], api: "DBMS_PERF.REPORT_SESSION",
                   summary: L10n.tr("Aktywność, zapytania monitorowane i metryki jednej sesji."),
                   note: L10n.tr("Tylko XML: przeglądarka Oracle nie wyświetla aktywnej wersji tego raportu („Not a sfx file”), a DBMS_REPORT nie zamienia go na HTML ani tekst (D223).")),
        PerfReport("perf.realtimeADDM", L10n.tr("Real-Time ADDM"), group: L10n.tr("Bieżąca praca"), scope: .global, need: .diagnostics, minMajor: 12, formats: [.xml],
                   api: "DBMS_ADDM.REAL_TIME_ADDM_REPORT",
                   summary: L10n.tr("Analiza ADDM ostatnich 5 minut z danych w pamięci."),
                   note: L10n.tr("Oracle zwraca raport w XML; aktywna wersja kończy się stroną 404 na serwerze Oracle (D223).")),
        PerfReport("perf.monitorList", L10n.tr("SQL Monitor — lista"), group: L10n.tr("Bieżąca praca"), scope: .global, need: .tuning, formats: [.html, .text, .xml],
                   parameters: [.timeWindow], api: "DBMS_SQLTUNE.REPORT_SQL_MONITOR_LIST",
                   summary: L10n.tr("Monitorowane zapytania i operacje bazy w oknie czasu.")),
        PerfReport("perf.statsOps", L10n.tr("Operacje statystyk optymalizatora"), group: L10n.tr("Optymalizator"), scope: .global, need: .none, minMajor: 12,
                   formats: [.html, .text, .xml], parameters: [.days], api: "DBMS_STATS.REPORT_STATS_OPERATIONS",
                   summary: L10n.tr("Zbieranie statystyk (ręczne i automatyczne) z ostatnich dni: czas, obiekty, błędy.")),
        PerfReport("perf.autoTuning", L10n.tr("Automatyczny SQL Tuning"), group: L10n.tr("Optymalizator"), scope: .global, need: .tuning, formats: [.text],
                   api: "DBMS_AUTO_SQLTUNE.REPORT_AUTO_TUNING_TASK / DBMS_SQLTUNE.REPORT_AUTO_TUNING_TASK",
                   summary: L10n.tr("Wynik ostatniego przebiegu automatycznego doradcy SQL Tuning (SYS_AUTO_SQL_TUNING_TASK).")),
        PerfReport("perf.spmEvolve", L10n.tr("Ewolucja planów SPM"), group: L10n.tr("Optymalizator"), scope: .global, need: .none, minMajor: 12, formats: [.html, .text, .xml],
                   api: "DBMS_SPM.REPORT_AUTO_EVOLVE_TASK",
                   summary: L10n.tr("Wynik ostatniego automatycznego zadania ewolucji SQL Plan Baselines.")),
    ]

    public static var all: [PerfReport] { sqlReports + globalReports }
    public static func report(_ id: String) -> PerfReport? { all.first { $0.id == id } }
}

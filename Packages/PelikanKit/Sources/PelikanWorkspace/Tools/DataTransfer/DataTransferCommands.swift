import Foundation
import PelikanDB

/// Narzędzia danych otwierane w osobnych oknach.
public enum DataTransferTool: String, Sendable, CaseIterable {
    case exportTables, importTables, textImporter, excelImporter, dataGenerator, compareTableData
}

/// Komendy narzędzi danych (PD-TOOL-003…013). Wszystkie dla użytkownika (agent — Brak): zmieniają dane albo pliki.
@MainActor
public enum DataTransferCommands {
    /// Połączenie narzędzia: aktywnego okna albo główne (`Workspace.toolConnection()`).
    public static func connection(_ ws: Workspace) -> UUID? { ws.toolConnection() }

    /// Przeznaczenie sesji narzędzi danych (osobna od okien użytkownika — import zatwierdza własne transakcje).
    public static let sessionPurpose = "dane"

    /// Sesja narzędzi danych na wskazanym połączeniu (bez wskazanego — połączenie narzędzia).
    public static func session(_ ws: Workspace, connection: UUID? = nil) async throws -> any DatabaseSession {
        try await ws.toolSession(sessionPurpose, connection: connection ?? ws.toolConnection())
    }

    static func open(_ id: CommandID, _ title: String, _ tool: DataTransferTool, summary: String, feature: String) -> Command {
        Command(CommandDescriptor(id: id, title: title, category: .tools, agent: .none, effect: .uiState, summary: summary, feature: feature),
                validate: { connection($0) != nil }) { ctx in
            ctx.ui?.showDataTransfer(tool)
            return .ok
        }
    }

    static var all: [Command] {
        [
            open("tools.exportTables", L10n.tr("Eksport tabel…"), .exportTables,
                 summary: L10n.tr("Eksport tabel jako SQL Inserts, w formacie własnym Pelikana albo przez Data Pump (kolejność wg kluczy obcych)."),
                 feature: "PD-TOOL-003"),
            open("tools.importTables", L10n.tr("Import tabel…"), .importTables,
                 summary: L10n.tr("Import skryptu SQL Inserts w oknie poleceń, pliku w formacie własnym z wyborem tabel albo zrzutu Data Pump."),
                 feature: "PD-TOOL-006"),
            open("tools.textImporter", L10n.tr("Import tekstu…"), .textImporter,
                 summary: L10n.tr("Import pliku tekstowego (CSV, TSV) do tabeli: wykrywanie formatu, mapowanie pól, filtr, duplikaty, skrypt."),
                 feature: "PD-TOOL-008"),
            open("tools.excelImporter", L10n.tr("Import z Excela…"), .excelImporter,
                 summary: L10n.tr("Import arkusza xlsx albo tekstu wklejonego z Excela do tabeli z mapowaniem kolumn."),
                 feature: "PD-TOOL-009"),
            open("tools.dataGenerator", L10n.tr("Generator danych…"), .dataGenerator,
                 summary: L10n.tr("Generuje dane testowe dla tabel (wzorce, funkcje, zbiory, master/detail) — podgląd, skrypt SQL albo zapis do bazy."),
                 feature: "PD-TOOL-011"),
            open("tools.compareTableData", L10n.tr("Porównaj dane tabel…"), .compareTableData,
                 summary: L10n.tr("Porównuje dane tabel ze schematem docelowym (także na innym połączeniu) po kluczu głównym; skrypt albo aktualizacja celu."),
                 feature: "PD-TOOL-013"),
        ]
    }
}

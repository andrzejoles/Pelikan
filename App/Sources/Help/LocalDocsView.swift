import AppKit
import PelikanWorkspace
import SwiftUI

/// Stan okna dokumentacji lokalnej (D216): jedno okno; kolejne F1 podmienia zapytanie i wyszukuje od nowa. Wyniki,
/// zaznaczenie i treść sekcji są w modelu — komendy okna („Kopiuj”, „Cała sekcja”, „Otwórz online”) widzą to samo
/// co okno, także gdy narzędzie przeniesiono między dokiem a osobnym oknem.
@MainActor @Observable
final class LocalDocsModel {
    static let shared = LocalDocsModel()
    var query = ""
    /// Zmienia się przy każdym zleceniu wyszukiwania z zewnątrz (F1, komenda).
    var request = 0
    var version = "19c"
    /// Wersja ustawiona z ustawień raz (przy pierwszym otwarciu); potem wybór w oknie — także przy wyszukiwaniu z F1.
    var versionInitialized = false
    /// Okno widoczne — komendy okna („Kopiuj”, „Cała sekcja”, „Otwórz online”) działają tylko na tym, co widać.
    var isOpen = false
    var results: [DocFragment] = []
    var selection: DocFragment.ID? {
        didSet { if selection != oldValue { detail = nil } }
    }
    /// Cała sekcja wybranego fragmentu (nil — sam fragment).
    var detail: String?
    var message = ""
    /// Wywołania serwera w toku (wskaźnik pracy) i numery najnowszych żądań — wynik starszego żądania jest pomijany.
    private(set) var pending = 0
    private var searchRequest = 0
    private var sectionRequest = 0

    var busy: Bool { pending > 0 }
    var selected: DocFragment? { results.first { $0.id == selection } }
    /// Wybrany fragment (tekst fragmentu albo całej sekcji, adres online).
    var fragment: (text: String, link: URL?)? { isOpen ? selected.map { (detail ?? $0.text, $0.link) } : nil }

    func search(_ q: String) {
        query = q
        request += 1
    }

    func search(settings: LocalDocsSettings) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searchRequest += 1
        let request = searchRequest
        // Zły adres unieważnia też wyszukiwanie w toku (jego wynik nie nadpisze komunikatu).
        guard let endpoint = settings.endpoint else { message = LocalDocsError.badAddress(settings.url).localizedDescription; return }
        pending += 1
        defer { pending -= 1 }
        do {
            let found = try await LocalDocsClient.shared(for: endpoint).search(q, version: version, count: 10)
            guard request == searchRequest else { return }
            results = found
            selection = results.first?.id
            message = results.isEmpty ? L10n.tr("Nic nie znaleziono") : L10n.tr("Fragmentów: \(results.count)")
        } catch {
            // Zamknięcie okna w trakcie (anulowane zadanie) to nie błąd serwera — wyniki zostają.
            guard request == searchRequest, !Task.isCancelled else { return }
            results = []
            selection = nil
            message = error.localizedDescription + " " + L10n.tr("Dokumentacja online działa bez serwera (przycisk obok).")
        }
    }

    /// „Cała sekcja” albo z powrotem „Tylko fragment”.
    func toggleSection(settings: LocalDocsSettings) async {
        guard let f = selected else { return }
        if detail != nil { detail = nil; return }
        guard let endpoint = settings.endpoint else { return }
        sectionRequest += 1
        let request = sectionRequest
        pending += 1
        defer { pending -= 1 }
        do {
            let text = try await LocalDocsClient.shared(for: endpoint).section(f.chunk)
            // W międzyczasie wybrano inny fragment albo pobrano inną sekcję — ten wynik jest nieaktualny.
            guard request == sectionRequest, selection == f.id else { return }
            detail = text
        } catch {
            if request == sectionRequest, selection == f.id { message = error.localizedDescription }
        }
    }
}

/// Okno dokumentacji Oracle z lokalnego serwera MCP: wyszukiwanie, lista fragmentów (książka, sekcja), treść
/// fragmentu albo całej sekcji, strona online fragmentu.
struct LocalDocsView: View {
    let workspace: Workspace
    @Bindable var model: LocalDocsModel

    private var settings: LocalDocsSettings { workspace.settings.localDocs }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Wąski panel doku: wersja i „Szukaj” pod polem; wyniki nad treścią fragmentu.
            ViewThatFits(in: .horizontal) {
                HStack { queryField; searchControls }
                VStack(alignment: .leading, spacing: 4) {
                    queryField
                    HStack { searchControls; Spacer() }
                }
            }
            GeometryReader { g in
                if g.size.width < 560 {
                    VSplitView {
                        resultList.frame(minHeight: 120, idealHeight: 180)
                        detailPane.frame(minHeight: 160)
                    }
                } else {
                    HSplitView {
                        resultList.frame(minWidth: 170, idealWidth: 260)
                        detailPane.frame(minWidth: 240)
                    }
                }
            }
            HStack {
                Text(model.message).font(.uiSecondary).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                Spacer()
                Button(L10n.tr("Dokumentacja online")) { workspace.perform("help.localDocsSearchOnline") }
                    .disabled(model.query.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help(L10n.tr("Szuka tych samych słów na docs.oracle.com"))
            }
        }
        .padding(10)
        .frame(minWidth: 320, minHeight: 380)
        .onAppear { model.isOpen = true }
        .onDisappear { model.isOpen = false }
        .task(id: model.request) {
            if !model.versionInitialized {
                model.version = settings.version
                model.versionInitialized = true
            }
            // Wykonanie zlecenia komendy (F1, „Szukaj”, paleta) — samo wyszukiwanie.
            if !model.query.trimmingCharacters(in: .whitespaces).isEmpty { await model.search(settings: settings) }
        }
    }

    private var queryField: some View {
        TextField(L10n.tr("Szukaj w dokumentacji Oracle (po angielsku, np. DBMS_SCHEDULER.CREATE_JOB repeat_interval)"), text: $model.query)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 200)
            .onSubmit { search() }
    }

    private var searchControls: some View {
        HStack {
            Picker(L10n.tr("Wersja"), selection: $model.version) {
                ForEach(LocalDocsSettings.versions, id: \.self) { v in Text(v == "all" ? L10n.tr("wszystkie") : v).tag(v) }
            }
            .fixedSize()
            Button(L10n.tr("Szukaj")) { search() }
                .disabled(model.query.trimmingCharacters(in: .whitespaces).isEmpty || model.busy)
            if model.busy { ProgressView().controlSize(.small) }
        }
        .fixedSize()
    }

    private var resultList: some View {
        List(model.results, selection: $model.selection) { f in
            VStack(alignment: .leading, spacing: 2) {
                Text(f.heading).lineLimit(2)
                Text(f.title).font(.uiSecondary).foregroundStyle(.secondary).lineLimit(1)
            }
            .tag(f.id)
        }
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let f = model.selected {
                Text(f.section).font(.uiSecondary).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(3)
                ScrollView {
                    DocText(text: model.detail ?? f.text).frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 6)
                }
                // Przyciski w wąskim panelu w dwóch wierszach (bez ucinania „Otwórz online”).
                ViewThatFits(in: .horizontal) {
                    HStack { sectionButtons(); Spacer(); openButton(f) }
                    VStack(alignment: .leading, spacing: 4) { HStack { sectionButtons() }; openButton(f) }
                }
            } else {
                Text(model.results.isEmpty ? L10n.tr("Wpisz szukane słowa albo naciśnij F1 na słowie w edytorze.") : L10n.tr("Wybierz fragment"))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder private func sectionButtons() -> some View {
        Button(model.detail == nil ? L10n.tr("Cała sekcja") : L10n.tr("Tylko fragment")) {
            workspace.perform("help.localDocsSection")
        }
        Button(L10n.tr("Kopiuj")) { workspace.perform("help.localDocsCopy") }
    }

    @ViewBuilder private func openButton(_ f: DocFragment) -> some View {
        if let link = f.link {
            Button(L10n.tr("Otwórz online")) { workspace.perform("help.localDocsOpenOnline") }
                .help(link.absoluteString)
        }
    }

    /// Wyszukiwanie z okna — komenda „Dokumentacja Oracle (lokalna)” z zapytaniem (paleta, makra, historia).
    private func search() { workspace.perform("help.localDocs", CommandArguments(["query": .string(model.query)])) }

}

/// Tekst dokumentacji: nagłówki „## …” pogrubione, reszta czcionką kodu (składnia i przykłady zachowują układ).
private struct DocText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("#") {
                    Text(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)).font(.headline).padding(.top, 4)
                } else {
                    Text(line.isEmpty ? " " : line).font(.code)
                }
            }
        }
        .textSelection(.enabled)
    }
}


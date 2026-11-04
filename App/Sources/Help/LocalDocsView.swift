import AppKit
import PelikanWorkspace
import SwiftUI

/// Stan okna dokumentacji lokalnej (D216): jedno okno; kolejne F1 podmienia zapytanie i wyszukuje od nowa.
@MainActor @Observable
final class LocalDocsModel {
    static let shared = LocalDocsModel()
    var query = ""
    /// Zmienia się przy każdym zleceniu wyszukiwania z zewnątrz (F1, komenda).
    var request = 0
    /// Wybrany fragment (tekst fragmentu albo całej sekcji, adres online) — komendy „Kopiuj” i „Otwórz online”.
    var fragment: (text: String, link: URL?)?

    func search(_ q: String) {
        query = q
        request += 1
    }
}

/// Okno dokumentacji Oracle z lokalnego serwera MCP: wyszukiwanie, lista fragmentów (książka, sekcja), treść
/// fragmentu albo całej sekcji, strona online fragmentu.
struct LocalDocsView: View {
    let workspace: Workspace
    @Bindable var model: LocalDocsModel
    @State private var version = "19c"
    @State private var results: [DocFragment] = []
    @State private var selection: DocFragment.ID?
    @State private var detail: String?
    /// Wywołania serwera w toku (wskaźnik pracy) i numery najnowszych żądań — wynik starszego żądania jest pomijany.
    @State private var pending = 0
    @State private var searchRequest = 0
    @State private var sectionRequest = 0
    private var busy: Bool { pending > 0 }
    @State private var message = ""

    private var selected: DocFragment? { results.first { $0.id == selection } }
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
                Text(message).font(.uiSecondary).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                Spacer()
                Button(L10n.tr("Dokumentacja online")) { openOnline() }
                    .disabled(model.query.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help(L10n.tr("Szuka tych samych słów na docs.oracle.com"))
            }
        }
        .padding(10)
        .frame(minWidth: 320, minHeight: 380)
        .task(id: model.request) {
            version = settings.version
            if !model.query.trimmingCharacters(in: .whitespaces).isEmpty { await search() }
        }
        .onChange(of: selection) { detail = nil }
        // Fragment dla komend okna („Kopiuj”, „Otwórz online”).
        .onChange(of: "\(selection.map(String.init) ?? "")|\(detail ?? "")", initial: true) {
            model.fragment = selected.map { (detail ?? $0.text, $0.link) }
        }
        .onDisappear { model.fragment = nil }
    }

    private var queryField: some View {
        TextField(L10n.tr("Szukaj w dokumentacji Oracle (po angielsku, np. DBMS_SCHEDULER.CREATE_JOB repeat_interval)"), text: $model.query)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 200)
            .onSubmit { Task { await search() } }
    }

    private var searchControls: some View {
        HStack {
            Picker(L10n.tr("Wersja"), selection: $version) {
                ForEach(LocalDocsSettings.versions, id: \.self) { v in Text(v == "all" ? L10n.tr("wszystkie") : v).tag(v) }
            }
            .fixedSize()
            Button(L10n.tr("Szukaj")) { Task { await search() } }
                .disabled(model.query.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            if busy { ProgressView().controlSize(.small) }
        }
        .fixedSize()
    }

    private var resultList: some View {
        List(results, selection: $selection) { f in
            VStack(alignment: .leading, spacing: 2) {
                Text(f.heading).lineLimit(2)
                Text(f.title).font(.uiSecondary).foregroundStyle(.secondary).lineLimit(1)
            }
            .tag(f.id)
        }
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let f = selected {
                Text(f.section).font(.uiSecondary).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(3)
                ScrollView {
                    DocText(text: detail ?? f.text).frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 6)
                }
                // Przyciski w wąskim panelu w dwóch wierszach (bez ucinania „Otwórz online”).
                ViewThatFits(in: .horizontal) {
                    HStack { sectionButtons(f); Spacer(); openButton(f) }
                    VStack(alignment: .leading, spacing: 4) { HStack { sectionButtons(f) }; openButton(f) }
                }
            } else {
                Text(results.isEmpty ? L10n.tr("Wpisz szukane słowa albo naciśnij F1 na słowie w edytorze.") : L10n.tr("Wybierz fragment"))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder private func sectionButtons(_ f: DocFragment) -> some View {
        Button(detail == nil ? L10n.tr("Cała sekcja") : L10n.tr("Tylko fragment")) {
            if detail == nil { Task { await loadSection(f) } } else { detail = nil }
        }
        Button(L10n.tr("Kopiuj")) { workspace.perform("help.localDocsCopy") }
    }

    @ViewBuilder private func openButton(_ f: DocFragment) -> some View {
        if let link = f.link {
            Button(L10n.tr("Otwórz online")) { workspace.perform("help.localDocsOpenOnline") }
                .help(link.absoluteString)
        }
    }

    private func search() async {
        let q = model.query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        guard let endpoint = settings.endpoint else { message = LocalDocsError.badAddress(settings.url).localizedDescription; return }
        searchRequest += 1
        let request = searchRequest
        pending += 1
        defer { pending -= 1 }
        do {
            let found = try await LocalDocsClient.shared(for: endpoint).search(q, version: version, count: 10)
            guard request == searchRequest else { return }
            results = found
            selection = results.first?.id
            message = results.isEmpty ? L10n.tr("Nic nie znaleziono") : L10n.tr("Fragmentów: \(results.count)")
        } catch {
            guard request == searchRequest else { return }
            results = []
            message = error.localizedDescription + " " + L10n.tr("Dokumentacja online działa bez serwera (przycisk obok).")
        }
    }

    private func loadSection(_ f: DocFragment) async {
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

    private func openOnline() {
        let q = model.query.trimmingCharacters(in: .whitespaces)
        let parts = q.split(separator: " ").map(String.init)
        if let url = OracleDocs.url(for: parts.first ?? q, next: parts.dropFirst().first, release: workspace.settings.oracleDocsRelease) {
            NSWorkspace.shared.open(url)
        }
    }
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


import AppKit
import Charts
import PelikanDB
import PelikanWorkspace
import SwiftUI

/// Okno wykresu (UG 13, PD-GRAPH-001): dane z karty wyników okna SQL, kreator osi (kategoria, serie, typ, agregacja),
/// styl (kolory, legenda, wartości), szablony w katalogu danych, auto-odświeżanie przez ponowne wykonanie polecenia
/// w oknie SQL, eksport PNG/PDF/schowek.
struct GraphView: View {
    let workspace: Workspace
    let document: PelikanWorkspace.Document
    @State var tab: ResultTab
    @State private var definition: ChartDefinition
    @State private var source: ExportData
    @State private var templates: [ChartDefinition] = []
    @State private var message = ""

    init(workspace: Workspace, document: PelikanWorkspace.Document, tab: ResultTab) {
        self.workspace = workspace
        self.document = document
        _tab = State(initialValue: tab)
        let data = tab.grid?.exportData(title: tab.title) ?? ExportData(title: tab.title, columns: [], rows: [])
        _source = State(initialValue: data)
        _definition = State(initialValue: ChartBuilder.suggest(data.columns, name: tab.title))
    }

    private var data: ChartData { ChartBuilder.build(definition, data: source, format: workspace.settings.valueFormat) }
    private var columnNames: [String] { source.columns.map(\.name) }

    var body: some View {
        HSplitView {
            settings.frame(minWidth: 260, idealWidth: 280, maxWidth: 340)
            VStack(alignment: .leading, spacing: 6) {
                if !definition.title.isEmpty { Text(definition.title).font(.headline) }
                chart.frame(minWidth: 420, minHeight: 320)
                HStack {
                    Text(message.isEmpty ? L10n.tr("Wierszy: \(source.rows.count), kategorii: \(data.categories.count)") : message)
                        .font(.caption).foregroundStyle(.secondary)
                    if data.skipped > 0 { Text(L10n.tr("pominięto wartości nieliczbowe: \(data.skipped)")).font(.caption).foregroundStyle(.orange) }
                    Spacer()
                    Button(L10n.tr("Odśwież")) { Task { await refresh() } }
                    Menu(L10n.tr("Eksport")) {
                        Button("PNG…") { export(pdf: false) }
                        Button("PDF…") { export(pdf: true) }
                        Button(L10n.tr("Kopiuj obraz")) { copyImage() }
                    }
                    .fixedSize()
                }
            }
            .padding(10)
        }
        .frame(minWidth: 760, minHeight: 440)
        .task { templates = ChartTemplateStore.load(from: workspace.dataDirectory) }
        .task(id: definition.refreshSeconds) {
            guard definition.refreshSeconds > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(definition.refreshSeconds))
                await refresh()
            }
        }
    }

    // MARK: Kreator

    private var settings: some View {
        Form {
            Section(L10n.tr("Wykres")) {
                TextField(L10n.tr("Tytuł"), text: $definition.title)
                Picker(L10n.tr("Typ"), selection: $definition.kind) { ForEach(ChartKind.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                Picker(L10n.tr("Kategoria (oś X)"), selection: $definition.categoryColumn) {
                    Text(L10n.tr("Numer wiersza")).tag(String?.none)
                    ForEach(columnNames, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                Picker(L10n.tr("Agregacja"), selection: $definition.aggregation) {
                    ForEach(ChartAggregation.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            Section(L10n.tr("Serie (oś Y)")) {
                ForEach(columnNames.filter { $0 != definition.categoryColumn }, id: \.self) { name in
                    Toggle(name, isOn: Binding(get: { definition.seriesColumns.contains(name) }, set: { on in
                        if on { definition.seriesColumns.append(name) } else { definition.seriesColumns.removeAll { $0 == name } }
                    }))
                    .toggleStyle(.checkbox)
                }
            }
            Section(L10n.tr("Styl")) {
                Toggle(L10n.tr("Słupki skumulowane"), isOn: $definition.stacked).disabled(definition.kind != .bar)
                Toggle(L10n.tr("Legenda"), isOn: $definition.showLegend)
                Toggle(L10n.tr("Wartości przy punktach"), isOn: $definition.showValues)
                ForEach(Array(definition.seriesColumns.enumerated()), id: \.element) { i, name in
                    ColorPicker(name, selection: colorBinding(i))
                }
                Stepper(definition.refreshSeconds == 0 ? L10n.tr("Auto-odświeżanie: wyłączone") : L10n.tr("Auto-odświeżanie co \(definition.refreshSeconds) s"),
                        value: $definition.refreshSeconds, in: 0...3600, step: 5)
            }
            Section(L10n.tr("Szablony")) {
                Menu(L10n.tr("Zastosuj szablon")) {
                    ForEach(templates) { t in Button(t.name) { apply(t) } }
                }
                .disabled(templates.isEmpty)
                HStack {
                    TextField(L10n.tr("Nazwa szablonu"), text: $definition.name)
                    Button(L10n.tr("Zapisz")) { saveTemplate() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func colorBinding(_ i: Int) -> Binding<Color> {
        Binding(get: {
            i < definition.colors.count ? Color(red: definition.colors[i].red, green: definition.colors[i].green, blue: definition.colors[i].blue) : Self.palette[i % Self.palette.count]
        }, set: { c in
            let ns = NSColor(c).usingColorSpace(.sRGB) ?? .systemBlue
            while definition.colors.count <= i {
                let d = NSColor(Self.palette[definition.colors.count % Self.palette.count]).usingColorSpace(.sRGB) ?? .systemBlue
                definition.colors.append(RGBColor(red: d.redComponent, green: d.greenComponent, blue: d.blueComponent))
            }
            definition.colors[i] = RGBColor(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent)
        })
    }

    static let palette: [Color] = [.blue, .orange, .green, .red, .purple, .teal, .pink, .brown]

    private var seriesColors: [Color] {
        definition.seriesColumns.indices.map { i in
            i < definition.colors.count ? Color(red: definition.colors[i].red, green: definition.colors[i].green, blue: definition.colors[i].blue) : Self.palette[i % Self.palette.count]
        }
    }

    // MARK: Wykres

    @ViewBuilder private var chart: some View {
        let d = data
        let base = Chart(d.points) { p in
            switch definition.kind {
            case .bar:
                if definition.stacked {
                    BarMark(x: .value(L10n.tr("Kategoria"), p.category), y: .value(L10n.tr("Wartość"), p.value))
                        .foregroundStyle(by: .value(L10n.tr("Seria"), p.series))
                        .annotation(position: .top) { if definition.showValues { Text(Self.format(p.value)).font(.caption2) } }
                } else {
                    BarMark(x: .value(L10n.tr("Kategoria"), p.category), y: .value(L10n.tr("Wartość"), p.value))
                        .foregroundStyle(by: .value(L10n.tr("Seria"), p.series))
                        .position(by: .value(L10n.tr("Seria"), p.series))
                        .annotation(position: .top) { if definition.showValues { Text(Self.format(p.value)).font(.caption2) } }
                }
            case .line:
                LineMark(x: .value(L10n.tr("Kategoria"), p.category), y: .value(L10n.tr("Wartość"), p.value))
                    .foregroundStyle(by: .value(L10n.tr("Seria"), p.series))
                    .symbol(by: .value(L10n.tr("Seria"), p.series))
                    .annotation(position: .top) { if definition.showValues { Text(Self.format(p.value)).font(.caption2) } }
            case .area:
                AreaMark(x: .value(L10n.tr("Kategoria"), p.category), y: .value(L10n.tr("Wartość"), p.value))
                    .foregroundStyle(by: .value(L10n.tr("Seria"), p.series))
            case .point:
                PointMark(x: .value(L10n.tr("Kategoria"), p.category), y: .value(L10n.tr("Wartość"), p.value))
                    .foregroundStyle(by: .value(L10n.tr("Seria"), p.series))
                    .annotation(position: .top) { if definition.showValues { Text(Self.format(p.value)).font(.caption2) } }
            case .pie:
                // Wykres kołowy: pierwsza seria, wycinek na kategorię.
                if p.series == d.series.first {
                    SectorMark(angle: .value(L10n.tr("Wartość"), max(0, p.value)), innerRadius: .ratio(0.4))
                        .foregroundStyle(by: .value(L10n.tr("Kategoria"), p.category))
                        .annotation(position: .overlay) { if definition.showValues { Text(Self.format(p.value)).font(.caption2) } }
                }
            }
        }
        if definition.kind == .pie {
            base.chartLegend(definition.showLegend ? .visible : .hidden)
        } else {
            base.chartForegroundStyleScale(domain: d.series, range: seriesColors)
                .chartXScale(domain: d.categories)
                .chartLegend(definition.showLegend ? .visible : .hidden)
        }
    }

    static func format(_ v: Double) -> String {
        v == v.rounded() && abs(v) < 1e15 ? String(Int64(v)) : String(format: "%.2f", v)
    }

    // MARK: Akcje

    private func apply(_ t: ChartDefinition) {
        var d = t
        d.id = definition.id
        // Kolumny szablonu, których nie ma w tym wyniku, są pomijane.
        let names = Set(columnNames.map { $0.uppercased() })
        if let c = d.categoryColumn, !names.contains(c.uppercased()) { d.categoryColumn = definition.categoryColumn }
        d.seriesColumns = d.seriesColumns.filter { names.contains($0.uppercased()) }
        if d.seriesColumns.isEmpty { d.seriesColumns = definition.seriesColumns }
        definition = d
    }

    private func saveTemplate() {
        do {
            try ChartTemplateStore.upsert(definition, in: workspace.dataDirectory)
            templates = ChartTemplateStore.load(from: workspace.dataDirectory)
            message = L10n.tr("Zapisano szablon „\(definition.name)”")
        } catch { message = error.localizedDescription }
    }

    private func refresh() async {
        do {
            if let fresh = try await workspace.reexecute(tab, in: document), let grid = fresh.grid {
                tab = fresh
                source = grid.exportData(title: fresh.title)
                message = L10n.tr("Odświeżono: \(Date().formatted(date: .omitted, time: .standard))")
            }
        } catch { message = error.localizedDescription }
    }

    @MainActor private func renderer() -> ImageRenderer<some View> {
        let r = ImageRenderer(content: chart.frame(width: 900, height: 560).padding(16).background(Color.white))
        r.scale = 2
        return r
    }

    private func export(pdf: Bool) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (definition.title.isEmpty ? definition.name : definition.title) + (pdf ? ".pdf" : ".png")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let r = renderer()
        if pdf {
            r.render { size, draw in
                var box = CGRect(origin: .zero, size: size)
                guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
                ctx.beginPDFPage(nil)
                draw(ctx)
                ctx.endPDFPage()
                ctx.closePDF()
            }
        } else if let image = r.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }

    private func copyImage() {
        guard let image = renderer().nsImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
}

/// Wyjście narzędzia użytkownika (PD-TOOL-017).
struct ToolOutputView: View {
    let text: String
    let status: Int32

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.tr("Kod wyjścia: \(status)")).font(.caption).foregroundStyle(status == 0 ? Color.secondary : Color.red)
            ScrollView {
                Text(text.isEmpty ? L10n.tr("(brak wyjścia)") : text).font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(4)
            }
        }
        .padding(10)
        .frame(minWidth: 520, minHeight: 300)
    }
}

/// Lista narzędzi użytkownika (Narzędzia › Narzędzia użytkownika…): programy zewnętrzne ze zmiennymi i bloki SQL.
struct UserToolsView: View {
    let workspace: Workspace
    @State private var tools: [UserTool] = []
    @State private var selection: UserTool.ID?

    private var index: Int? { tools.firstIndex { $0.id == selection } }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading) {
                List(tools, selection: $selection) { Text($0.name).tag($0.id) }
                HStack {
                    Button { tools.append(UserTool(name: L10n.tr("Nowe narzędzie"))); selection = tools.last?.id } label: { Image(systemName: "plus") }.iconLabel(L10n.tr("Dodaj"))
                    Button { tools.removeAll { $0.id == selection } } label: { Image(systemName: "minus") }.iconLabel(L10n.tr("Usuń")).disabled(selection == nil)
                }
            }
            .frame(minWidth: 180, idealWidth: 200)
            Group {
                if let i = index { editor($tools[i]) } else { Text(L10n.tr("Wybierz albo dodaj narzędzie")).foregroundStyle(.secondary) }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(L10n.tr("Zmienne: ") + UserToolContext.variables.map(\.0).joined(separator: " ")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.tr("Zapisz")) { workspace.updateUserTools(tools) }.keyboardShortcut(.defaultAction)
            }
            .padding(8)
        }
        .frame(minWidth: 680, minHeight: 420)
        .onAppear { tools = workspace.settings.userTools }
    }

    private func editor(_ t: Binding<UserTool>) -> some View {
        Form {
            TextField(L10n.tr("Nazwa"), text: t.name)
            Picker(L10n.tr("Rodzaj"), selection: t.kind) {
                Text(L10n.tr("Program zewnętrzny")).tag(UserTool.Kind.external)
                Text(L10n.tr("Blok SQL dla sesji")).tag(UserTool.Kind.session)
            }
            if t.wrappedValue.kind == .external {
                TextField(L10n.tr("Program (ścieżka albo nazwa)"), text: t.program).font(.system(.body, design: .monospaced))
                TextField(L10n.tr("Argumenty (każdy w osobnej linii)"), text: Binding(get: { t.wrappedValue.arguments.joined(separator: "\n") },
                                                                                   set: { t.wrappedValue.arguments = $0.components(separatedBy: "\n") }),
                          axis: .vertical).font(.system(.body, design: .monospaced)).lineLimit(2...8)
                TextField(L10n.tr("Katalog roboczy"), text: t.workingDirectory)
                Picker(L10n.tr("Wyjście"), selection: t.output) {
                    Text(L10n.tr("Pomiń")).tag(UserTool.Output.none)
                    Text(L10n.tr("Okno wyjścia")).tag(UserTool.Output.outputWindow)
                    Text(L10n.tr("Nowe okno")).tag(UserTool.Output.newWindow)
                }
                Text(L10n.tr("Program uruchamiany bez powłoki; argumenty nie są cytowane ani interpretowane. Do programu nie trafiają hasła ani dane połączenia — tylko alias."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                TextField(L10n.tr("Blok SQL"), text: t.sql, axis: .vertical).font(.system(.body, design: .monospaced)).lineLimit(4...12)
                Toggle(L10n.tr("Wykonaj od razu"), isOn: t.executeImmediately)
            }
            Toggle(L10n.tr("Zapisz plik okna przed uruchomieniem"), isOn: t.saveBeforeRun)
        }
        .formStyle(.grouped)
    }
}

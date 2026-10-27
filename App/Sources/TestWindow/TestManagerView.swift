import AppKit
import PelikanWorkspace
import SwiftUI
import UniformTypeIdentifiers

/// Test Manager (UG 24.16, PD-TOOL-018): zestaw testów, edycja testu (blok, zmienne z wejściem i oczekiwaniem,
/// DBMS_OUTPUT, limit czasu), zmienne globalne, uruchomienie z wynikami, przejście do okna testu (debugowanie).
struct TestManagerView: View {
    let workspace: Workspace
    @State private var testSet = TestSet(name: L10n.tr("Nowy zestaw"))
    @State private var selection: TestCase.ID?
    @State private var results: [UUID: TestCaseResult] = [:]
    @State private var running = false
    @State private var file: URL?
    @State private var globalsText = ""

    private var index: Int? { testSet.cases.firstIndex { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(L10n.tr("Otwórz…")) { open() }
                Button(L10n.tr("Zapisz…")) { save() }
                Divider().frame(height: 18)
                Button(L10n.tr("Dodaj test")) {
                    let c = TestCase(name: L10n.tr("Test \(testSet.cases.count + 1)"), block: "begin\n  :wynik := 1;\nend;",
                                     variables: [TestCaseVariable(name: "wynik", type: .integer, expected: TestExpectation(.equals, "1"))])
                    testSet.cases.append(c)
                    selection = c.id
                }
                Button(L10n.tr("Usuń test")) { if let i = index { testSet.cases.remove(at: i) } }.disabled(index == nil)
                Spacer()
                Button(L10n.tr("Otwórz w oknie testu")) { openInTestWindow() }.disabled(index == nil)
                Button { Task { await run() } } label: { Label(L10n.tr("Uruchom"), systemImage: "play.fill") }.disabled(running || testSet.cases.isEmpty)
            }
            HSplitView {
                List(selection: $selection) {
                    ForEach(testSet.cases) { c in
                        HStack {
                            Image(systemName: results[c.id].map { $0.passed ? "checkmark.circle.fill" : "xmark.circle.fill" } ?? "circle")
                                .foregroundStyle(results[c.id].map { $0.passed ? Color.green : Color.red } ?? .secondary)
                            Text(c.name)
                        }
                        .tag(c.id)
                    }
                }
                .frame(minWidth: 200)
                editor.frame(minWidth: 460)
            }
            HStack {
                Text(L10n.tr("Zmienne globalne (NAZWA=wartość, po przecinku; w wejściu: &NAZWA)")).font(.uiSecondary)
                TextField("", text: $globalsText).textFieldStyle(.roundedBorder).onSubmit { applyGlobals() }
            }
            if !results.isEmpty {
                Text(L10n.tr("Udane: \(results.values.filter(\.passed).count) z \(results.count)")).font(.uiSecondary).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(minWidth: 820, minHeight: 520)
    }

    @ViewBuilder private var editor: some View {
        if let i = index {
            Form {
                TextField(L10n.tr("Nazwa"), text: $testSet.cases[i].name)
                TextEditor(text: $testSet.cases[i].block).font(.code).frame(minHeight: 120)
                Section(L10n.tr("Zmienne")) {
                    ForEach($testSet.cases[i].variables) { $v in
                        HStack {
                            TextField(L10n.tr("Nazwa"), text: $v.name).frame(width: 90)
                            Picker("", selection: $v.type) { ForEach(TestVariableType.allCases, id: \.self) { Text($0.displayName).tag($0) } }.frame(width: 110)
                            TextField(L10n.tr("Wejście (puste — NULL)"), text: Binding(get: { v.input ?? "" }, set: { v.input = $0.isEmpty ? nil : $0 }))
                            Picker("", selection: Binding(get: { v.expected?.op }, set: { op in v.expected = op.map { TestExpectation($0, v.expected?.value ?? "") } })) {
                                Text(L10n.tr("bez oczekiwania")).tag(TestExpectation.Operator?.none)
                                ForEach(TestExpectation.Operator.allCases, id: \.self) { Text($0.rawValue).tag(TestExpectation.Operator?.some($0)) }
                            }.frame(width: 140)
                            TextField(L10n.tr("Oczekiwane"), text: Binding(get: { v.expected?.value ?? "" }, set: { v.expected?.value = $0 }))
                                .disabled(v.expected == nil || v.expected?.op == .isNull || v.expected?.op == .isNotNull)
                        }
                    }
                    Button(L10n.tr("Dodaj zmienną")) { testSet.cases[i].variables.append(TestCaseVariable(name: "zmienna", type: .string)) }
                }
                TextField(L10n.tr("Oczekiwane DBMS_OUTPUT (wzorzec LIKE)"), text: Binding(get: { testSet.cases[i].expectedOutput ?? "" }, set: { testSet.cases[i].expectedOutput = $0.isEmpty ? nil : $0 }))
                TextField(L10n.tr("Limit czasu (s)"), value: $testSet.cases[i].maxSeconds, format: .number)
                if let r = results[testSet.cases[i].id] {
                    Section(L10n.tr("Wynik")) {
                        Text(r.passed ? L10n.tr("Udany (\(String(format: "%.2f", r.seconds)) s)") : r.failures.joined(separator: "\n"))
                            .foregroundStyle(r.passed ? .green : .red).textSelection(.enabled)
                        if !r.output.isEmpty { Text(r.output.joined(separator: "\n")).font(.code) }
                    }
                }
            }
        } else {
            Text(L10n.tr("Wybierz albo dodaj test")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func applyGlobals() {
        var g: [String: String] = [:]
        for pair in globalsText.split(separator: ",") {
            let p = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if p.count == 2, !p[0].isEmpty { g[p[0].uppercased()] = p[1] }
        }
        testSet.globals = g
    }

    private func run() async {
        guard let conn = workspace.sessions.mainConnectionID else { return }
        applyGlobals()
        running = true
        results = [:]
        _ = await TestManager.run(testSet, connectionID: conn, in: workspace) { r in results[r.id] = r }
        running = false
    }

    private func openInTestWindow() {
        guard let i = index else { return }
        let c = testSet.cases[i]
        let d = workspace.newDocument(.test, text: c.block)
        d.connectionID = workspace.sessions.mainConnectionID
        d.testVariables = c.variables.map { TestVariable(name: $0.name, type: $0.type, value: $0.input.map { TestManager.resolve($0, globals: testSet.globals) } ?? "", isNull: $0.input == nil) }
    }

    private func open() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [UTType(filenameExtension: "pts") ?? .json]
        guard p.runModal() == .OK, let url = p.url else { return }
        let s: TestSet
        do { s = try TestSet.decode(Data(contentsOf: url)) } catch { workspace.ui?.showError(error.localizedDescription); return }
        testSet = s
        file = url
        results = [:]
        globalsText = s.globals.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
    }

    private func save() {
        applyGlobals()
        let p = NSSavePanel()
        p.nameFieldStringValue = file?.lastPathComponent ?? "\(testSet.name).pts"
        guard p.runModal() == .OK, let url = p.url else { return }
        do { try testSet.encoded().write(to: url) } catch { workspace.ui?.showError(error.localizedDescription); return }
        file = url
    }
}

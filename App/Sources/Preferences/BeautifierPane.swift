import PelikanSQL
import PelikanWorkspace
import SwiftUI

/// Reguły formatera PL/SQL (UG 29.1–29.2, D174, D202) z podglądem na żywo: cztery przełączane przykłady (PL/SQL,
/// zapytania, DML, DDL) z kolorowaniem składni, numerami linii i linią prawego marginesu; linie zmienione ostatnią zmianą
/// ustawienia są podświetlone, miejsce usuniętych — czerwoną kreską; zmiana przełącza na przykład, w którym ją widać, i
/// przewija do niej; podświetlenie gaśnie po 5 s albo przy następnej zmianie (D202). Formatowanie automatyczne (UG 29.4).
struct BeautifierPane: View {
    let workspace: Workspace
    @State private var specialCase = ""
    /// Przykład podglądu (`BeautifierExamples.previews`), sformatowane przykłady i znaczniki ostatniej zmiany.
    @State private var sampleID = "plsql"
    @State private var formatted: [String: String] = [:]
    @State private var marks: [String: BeautifierExamples.Marks] = [:]
    /// Linia, do której podgląd przewija po zmianie (z licznikiem — ta sama linia po kolejnej zmianie też przewija).
    @State private var scrollTarget: (line: Int, serial: Int)?
    /// Numer ostatniej zmiany ustawień — podświetlenie zmian gaśnie po 5 s (zadanie anulowane przy następnej zmianie).
    @State private var changeSerial = 0

    private var options: BeautifierOptions { workspace.settings.beautifier }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Form {
                layout
                lists
                clauses
                alignment
                spacing
                letterCase
                Section(L10n.tr("Formatuj automatycznie")) {
                    Toggle(L10n.tr("Po otwarciu źródła z bazy"), isOn: setting(workspace, \.beautifier.afterLoad))
                    Toggle(L10n.tr("Przed kompilacją"), isOn: setting(workspace, \.beautifier.beforeCompile))
                    Toggle(L10n.tr("Przed zapisem do pliku"), isOn: setting(workspace, \.beautifier.beforeSave))
                }
            }
            .formStyle(.grouped)
            .frame(width: 390)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker(L10n.tr("Przykład podglądu"), selection: $sampleID) {
                        Text(verbatim: "PL/SQL").tag("plsql")
                        Text(L10n.tr("Zapytania")).tag("queries")
                        Text(verbatim: "DML").tag("dml")
                        Text(verbatim: "DDL").tag("ddl")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                }
                Text(L10n.tr("Podgląd — linie zmienione ostatnią zmianą są podświetlone przez 5 s, czerwona kreska oznacza usunięte linie, pionowa linia — prawy margines"))
                    .font(.uiSecondary).foregroundStyle(.secondary)
                previewView
            }
            .padding(10)
        }
        .onAppear {
            specialCase = options.specialCase.joined(separator: ", ")
            formatted = formatAll(options)
        }
        // Pole zapisywane przy każdej zmianie (jak reszta Preferencji), a zmiana z zestawu lub importu odświeża pole.
        .onChange(of: specialCase) { saveSpecialCase() }
        .onChange(of: options.specialCase) { _, new in
            if Self.parseSpecialCase(specialCase) != new { specialCase = new.joined(separator: ", ") }
        }
        .onChange(of: options) { old, new in
            let id = Self.changedOption(old, new)
            let before = formatted.isEmpty ? formatAll(old) : formatted
            let after = formatAll(new)
            var m: [String: BeautifierExamples.Marks] = [:]
            for s in BeautifierExamples.previews {
                m[s.id] = BeautifierExamples.marks(baseline: before[s.id] ?? "", current: after[s.id] ?? "")
            }
            formatted = after
            marks = m
            // Zmiana niewidoczna w bieżącym przykładzie — przykład tej opcji albo pierwszy, w którym coś się zmieniło.
            if m[sampleID]?.isEmpty ?? true {
                let preferred = id.flatMap { BeautifierExamples.previewOf[$0] }
                if let p = preferred, m[p]?.isEmpty == false {
                    sampleID = p
                } else if let other = BeautifierExamples.previews.first(where: { m[$0.id]?.isEmpty == false }) {
                    sampleID = other.id
                }
            }
            if let first = m[sampleID]?.first { scrollTarget = (first, (scrollTarget?.serial ?? 0) + 1) }
            changeSerial += 1
        }
        .task(id: changeSerial) {
            guard changeSerial > 0 else { return }
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { withAnimation { marks = [:] } }
        }
    }

    // MARK: Podgląd

    private var previewLines: [String] { (formatted[sampleID] ?? "").components(separatedBy: "\n") }

    /// Szerokość znaku czcionki kodu (linia marginesu i szerokość wierszy).
    private var charWidth: CGFloat {
        ("M" as NSString).size(withAttributes: [.font: InterfaceFonts.shared.code]).width
    }

    private var currentMarks: BeautifierExamples.Marks { marks[sampleID] ?? BeautifierExamples.Marks() }

    private var gutterWidth: CGFloat { CGFloat(String(previewLines.count).count + 1) * charWidth }

    private var rowWidth: CGFloat {
        let longest = previewLines.map(\.count).max() ?? 0
        return gutterWidth + 12 + CGFloat(max(options.rightMargin + 4, longest)) * charWidth
    }

    private var marginOffset: CGFloat { gutterWidth + 12 + CGFloat(options.rightMargin) * charWidth }

    private func previewRow(_ k: Int, _ line: String) -> some View {
        let m = currentMarks
        return HStack(spacing: 0) {
            Text(verbatim: "\(k + 1)")
                .foregroundStyle(.tertiary)
                .frame(width: gutterWidth, alignment: .trailing)
                .padding(.trailing, 12)
            Text(colored(line))
                .fixedSize()
        }
        .font(.code)
        .frame(width: rowWidth, alignment: .leading)
        .background(m.changed.contains(k) ? Color.yellow.opacity(0.35) : Color.clear)
        .overlay(alignment: .top) {
            if m.removedBefore.contains(k) { removedMark }
        }
    }

    private var removedMark: some View { Rectangle().fill(Color.red.opacity(0.8)).frame(height: 2) }

    private var previewLinesView: some View {
        let lines = previewLines
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { k, line in
                previewRow(k, line).id(k)
            }
            if currentMarks.removedBefore.contains(lines.count) { removedMark.frame(width: rowWidth) }
        }
        .overlay(alignment: .topLeading) {
            Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: 1).offset(x: marginOffset)
        }
    }

    private var previewView: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                previewLinesView
                    .padding(8)
                    .textSelection(.enabled)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .accessibilityLabel(L10n.tr("Podgląd formatowania"))
            .onChange(of: scrollTarget?.serial) {
                guard let line = scrollTarget?.line else { return }
                withAnimation { proxy.scrollTo(line, anchor: .center) }
            }
        }
    }

    /// Linia podglądu z kolorami składni jak w edytorze (bez stanu między liniami — przykłady nie mają wieloliniowych
    /// literałów ani komentarzy).
    private func colored(_ line: String) -> AttributedString {
        var out = AttributedString()
        let lexer = Lexer(line)
        for t in lexer.tokenize() {
            var part = AttributedString(lexer.string(t))
            if let c = SyntaxTheme.color(for: t.kind) { part.foregroundColor = Color(nsColor: c) }
            out += part
        }
        return out
    }

    private func formatAll(_ o: BeautifierOptions) -> [String: String] {
        Dictionary(uniqueKeysWithValues: BeautifierExamples.previews.map { ($0.id, format($0.code, o)) })
    }

    // MARK: Sekcje

    private var layout: some View {
        Section(L10n.tr("Układ")) {
            row("indent") {
                Stepper(value: setting(workspace, \.beautifier.indent), in: 1...8) { Text(L10n.tr("Wcięcie: \(options.indent)")) }
            }
            row("useTabs") { Toggle(L10n.tr("Wcięcie znakami tabulacji"), isOn: setting(workspace, \.beautifier.useTabs)) }
            row("rightMargin") {
                Stepper(value: setting(workspace, \.beautifier.rightMargin), in: 40...250, step: 10) {
                    Text(L10n.tr("Prawy margines: \(options.rightMargin)"))
                }
            }
            row("keepBlankLines") { Toggle(L10n.tr("Zachowuj puste linie"), isOn: setting(workspace, \.beautifier.keepBlankLines)) }
            row("maxBlankLines") {
                Stepper(value: setting(workspace, \.beautifier.maxBlankLines), in: 1...5) {
                    Text(L10n.tr("Najwięcej pustych linii z rzędu: \(options.maxBlankLines)"))
                }
                .disabled(!options.keepBlankLines)
            }
            row("blankLineBetweenSubprograms") {
                Toggle(L10n.tr("Pusta linia przed każdym podprogramem"), isOn: setting(workspace, \.beautifier.blankLineBetweenSubprograms))
            }
        }
    }

    private var lists: some View {
        Section(L10n.tr("Listy i przecinki")) {
            row("listLayout") {
                Picker(L10n.tr("Listy (SELECT, SET, ORDER BY)"), selection: setting(workspace, \.beautifier.listLayout)) { layoutOptions }
            }
            row("parameterDeclarations") {
                Picker(L10n.tr("Deklaracje parametrów"), selection: setting(workspace, \.beautifier.parameterDeclarations)) { layoutOptions }
            }
            row("callParameters") {
                Picker(L10n.tr("Parametry wywołań"), selection: setting(workspace, \.beautifier.callParameters)) { layoutOptions }
            }
            row("insertLists") {
                Picker(L10n.tr("Listy INSERT (kolumny, VALUES)"), selection: setting(workspace, \.beautifier.insertLists)) { layoutOptions }
            }
            row("commaBefore") { Toggle(L10n.tr("Przecinek na początku linii"), isOn: setting(workspace, \.beautifier.commaBefore)) }
        }
    }

    private var clauses: some View {
        Section(L10n.tr("Klauzule SQL i warunki")) {
            row("clauseLayout") {
                Picker(L10n.tr("Słowa klauzul (FROM, WHERE…)"), selection: setting(workspace, \.beautifier.clauseLayout)) {
                    Text(L10n.tr("Do lewej, elementy w kolumnie")).tag(BeautifierOptions.ClauseLayout.leftAligned)
                    Text(L10n.tr("Do prawej (rzeka)")).tag(BeautifierOptions.ClauseLayout.rightAligned)
                    Text(L10n.tr("W osobnej linii, elementy wcięte")).tag(BeautifierOptions.ClauseLayout.ownLine)
                }
            }
            row("andOrPosition") {
                Picker(L10n.tr("AND / OR"), selection: setting(workspace, \.beautifier.andOrPosition)) {
                    Text(L10n.tr("Na początku linii")).tag(BeautifierOptions.OperatorPosition.lineStart)
                    Text(L10n.tr("Na końcu linii")).tag(BeautifierOptions.OperatorPosition.lineEnd)
                }
            }
            row("joinConditionOnNewLine") {
                Toggle(L10n.tr("JOIN … ON: warunek w nowej linii"), isOn: setting(workspace, \.beautifier.joinConditionOnNewLine))
            }
            row("thenOnNewLine") { Toggle(L10n.tr("IF … THEN: THEN w nowej linii"), isOn: setting(workspace, \.beautifier.thenOnNewLine)) }
            row("caseLayout") {
                Picker(L10n.tr("Wyrażenie CASE"), selection: setting(workspace, \.beautifier.caseLayout)) {
                    Text(L10n.tr("W jednej linii")).tag(BeautifierOptions.CaseLayout.inline)
                    Text(L10n.tr("WHEN, ELSE, END w osobnych liniach")).tag(BeautifierOptions.CaseLayout.multiline)
                }
            }
        }
    }

    private var alignment: some View {
        Section(L10n.tr("Wyrównanie w kolumnach")) {
            row("alignDeclarations") {
                Toggle(L10n.tr("Deklaracje: typy i := / DEFAULT"), isOn: setting(workspace, \.beautifier.alignDeclarations))
            }
            row("alignParameters") {
                Toggle(L10n.tr("Parametry: tryb (IN/OUT), typ, DEFAULT"), isOn: setting(workspace, \.beautifier.alignParameters))
            }
            row("alignNamedArguments") {
                Toggle(L10n.tr("Parametry nazwane: =>"), isOn: setting(workspace, \.beautifier.alignNamedArguments))
            }
            row("alignAssignments") { Toggle(L10n.tr("Kolejne przypisania: :="), isOn: setting(workspace, \.beautifier.alignAssignments)) }
            row("alignAliases") { Toggle(L10n.tr("Aliasy w SELECT i FROM"), isOn: setting(workspace, \.beautifier.alignAliases)) }
            row("alignSetValues") { Toggle(L10n.tr("UPDATE … SET: ="), isOn: setting(workspace, \.beautifier.alignSetValues)) }
            row("alignTrailingComments") {
                Toggle(L10n.tr("Komentarze na końcu kolejnych linii"), isOn: setting(workspace, \.beautifier.alignTrailingComments))
            }
            Text(L10n.tr("Wyrównanie dotyczy elementów w osobnych liniach — przy parametrach i liście SELECT włącz „Element w linii”."))
                .font(.uiSecondary).foregroundStyle(.secondary)
        }
    }

    private var spacing: some View {
        Section(L10n.tr("Odstępy")) {
            row("spaceAroundOperators") {
                Toggle(L10n.tr("Spacje wokół operatorów (=, <>, +, ||…)"), isOn: setting(workspace, \.beautifier.spaceAroundOperators))
            }
            row("spaceAfterComma") { Toggle(L10n.tr("Spacja po przecinku"), isOn: setting(workspace, \.beautifier.spaceAfterComma)) }
            row("spaceInsideParentheses") {
                Toggle(L10n.tr("Spacje wewnątrz nawiasów"), isOn: setting(workspace, \.beautifier.spaceInsideParentheses))
            }
        }
    }

    private var letterCase: some View {
        Section(L10n.tr("Wielkość liter")) {
            row("keywordCase") { Picker(L10n.tr("Słowa kluczowe"), selection: setting(workspace, \.beautifier.keywordCase)) { caseOptions } }
            row("identifierCase") { Picker(L10n.tr("Identyfikatory"), selection: setting(workspace, \.beautifier.identifierCase)) { caseOptions } }
            row("dataTypeCase") {
                Picker(L10n.tr("Typy danych (NUMBER, VARCHAR2…)"), selection: setting(workspace, \.beautifier.dataTypeCase)) {
                    Text(L10n.tr("Jak słowa kluczowe")).tag(BeautifierOptions.WordCase?.none)
                    optionalCaseOptions
                }
            }
            row("functionCase") {
                Picker(L10n.tr("Funkcje wbudowane (NVL, TO_CHAR…)"), selection: setting(workspace, \.beautifier.functionCase)) {
                    Text(L10n.tr("Jak identyfikatory")).tag(BeautifierOptions.WordCase?.none)
                    optionalCaseOptions
                }
            }
            row("packageCase") {
                Picker(L10n.tr("Pakiety Oracle (DBMS_…, UTL_…)"), selection: setting(workspace, \.beautifier.packageCase)) {
                    Text(L10n.tr("Jak identyfikatory")).tag(BeautifierOptions.WordCase?.none)
                    optionalCaseOptions
                }
            }
            row("specialCase") {
                TextField(L10n.tr("Pisownia specjalna (po przecinku)"), text: $specialCase, prompt: Text("DBMS_Output, UTL_File"))
            }
            Text(L10n.tr("Literały, identyfikatory w cudzysłowie i komentarze nigdy nie są zmieniane."))
                .font(.uiSecondary).foregroundStyle(.secondary)
        }
    }

    /// Wiersz opcji: kliknięcie przełącza podgląd na przykład, w którym widać opcję.
    private func row<Content: View>(_ id: String, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .simultaneousGesture(TapGesture().onEnded {
                if let p = BeautifierExamples.previewOf[id] { sampleID = p }
            })
    }

    // MARK: Pomocnicze

    /// Pierwsza opcja z przykładem, której wartość się zmieniła.
    static func changedOption(_ a: BeautifierOptions, _ b: BeautifierOptions) -> String? {
        let old = Dictionary(uniqueKeysWithValues: Mirror(reflecting: a).children.compactMap { c in c.label.map { ($0, "\(c.value)") } })
        return Mirror(reflecting: b).children.first { c in
            guard let l = c.label else { return false }
            return old[l] != "\(c.value)" && BeautifierExamples.example(l) != nil
        }?.label
    }

    private func format(_ text: String, _ o: BeautifierOptions) -> String {
        (try? Beautifier.format(text, options: o)) ?? text
    }

    @ViewBuilder private var layoutOptions: some View {
        Text(L10n.tr("Element w linii")).tag(BeautifierOptions.ListLayout.onePerLine)
        Text(L10n.tr("Do marginesu")).tag(BeautifierOptions.ListLayout.fit)
    }

    @ViewBuilder private var caseOptions: some View {
        Text(L10n.tr("Bez zmian")).tag(BeautifierOptions.WordCase.unchanged)
        Text(L10n.tr("WIELKIE")).tag(BeautifierOptions.WordCase.upper)
        Text(L10n.tr("małe")).tag(BeautifierOptions.WordCase.lower)
        Text(L10n.tr("Pierwsza wielka")).tag(BeautifierOptions.WordCase.initCap)
    }

    @ViewBuilder private var optionalCaseOptions: some View {
        Text(L10n.tr("Bez zmian")).tag(BeautifierOptions.WordCase?.some(.unchanged))
        Text(L10n.tr("WIELKIE")).tag(BeautifierOptions.WordCase?.some(.upper))
        Text(L10n.tr("małe")).tag(BeautifierOptions.WordCase?.some(.lower))
        Text(L10n.tr("Pierwsza wielka")).tag(BeautifierOptions.WordCase?.some(.initCap))
    }

    private static func parseSpecialCase(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Tekst pola zostaje taki, jak wpisany (spacja po przecinku w trakcie pisania); do ustawień trafia lista.
    private func saveSpecialCase() {
        let list = Self.parseSpecialCase(specialCase)
        if list != options.specialCase { workspace.settings.beautifier.specialCase = list }
    }
}

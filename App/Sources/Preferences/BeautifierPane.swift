import PelikanSQL
import PelikanWorkspace
import SwiftUI

/// Reguły formatera PL/SQL (UG 29.1–29.2, D174) z podglądem na żywo: kod podglądu pokazuje każdą opcję, linie
/// zmienione ostatnią zmianą ustawienia są podświetlone, a opcja pod kursorem (albo ostatnio zmieniona) ma przykład
/// „teraz” i „po zmianie”. Formatowanie automatyczne (UG 29.4).
struct BeautifierPane: View {
    let workspace: Workspace
    @State private var specialCase = ""
    /// Opcja, której przykład jest pokazany (nazwa właściwości `BeautifierOptions`).
    @State private var focused = "keywordCase"
    @State private var preview = ""
    @State private var changed: Set<Int> = []

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
                example
                Text(L10n.tr("Podgląd — linie zmienione ostatnią zmianą są podświetlone")).font(.uiSecondary).foregroundStyle(.secondary)
                ScrollView([.vertical, .horizontal]) {
                    Text(highlighted)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .accessibilityLabel(L10n.tr("Podgląd formatowania"))
            }
            .padding(10)
        }
        .onAppear {
            specialCase = options.specialCase.joined(separator: ", ")
            preview = format(BeautifierExamples.preview, options)
        }
        // Pole zapisywane przy każdej zmianie (jak reszta Preferencji), a zmiana z zestawu lub importu odświeża pole.
        .onChange(of: specialCase) { saveSpecialCase() }
        .onChange(of: options.specialCase) { _, new in
            if Self.parseSpecialCase(specialCase) != new { specialCase = new.joined(separator: ", ") }
        }
        .onChange(of: options) { old, new in
            if let id = Self.changedOption(old, new) { focused = id }
            let next = format(BeautifierExamples.preview, new)
            changed = Set(TextDiff.lineStatus(baseline: preview, current: next).keys)
            preview = next
        }
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

    // MARK: Przykład opcji

    @ViewBuilder private var example: some View {
        if let e = BeautifierExamples.example(focused) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("Przykład opcji — wskaż albo zmień opcję po lewej")).font(.uiSecondary).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 8) {
                    exampleColumn(L10n.tr("Teraz"), format(e.snippet, options))
                    exampleColumn(L10n.tr("Po zmianie tej opcji"), format(e.snippet, e.variant(options)))
                }
            }
            .frame(height: 190)
        }
    }

    private func exampleColumn(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.uiSecondary.bold())
            ScrollView([.vertical, .horizontal]) {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(6)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
        }
        .frame(maxWidth: .infinity)
    }

    /// Wiersz opcji: wskazanie kursorem albo zmiana wartości pokazuje jej przykład.
    private func row<Content: View>(_ id: String, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .onHover { if $0 { focused = id } }
            .simultaneousGesture(TapGesture().onEnded { focused = id })
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

    private var highlighted: AttributedString {
        var out = AttributedString()
        for (k, line) in preview.components(separatedBy: "\n").enumerated() {
            var a = AttributedString(line + "\n")
            if changed.contains(k) { a.backgroundColor = Color.yellow.opacity(0.35) }
            out += a
        }
        return out
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

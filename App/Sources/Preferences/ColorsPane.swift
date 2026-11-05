import AppKit
import PelikanSQL
import PelikanWorkspace
import SwiftUI

/// Ustawienia › Kolory (D227): motywy kolorowania składni — lista wbudowanych i własnych (jasne i ciemne), wybór dla
/// trybu jasnego i ciemnego systemu, podgląd SQL, PL/SQL i Pro*C, kopia „Zapisz jako własny…” i edycja kolorów,
/// pogrubienia i kursywy motywu własnego, import i eksport.
struct ColorsPane: View {
    let workspace: Workspace
    @State private var selectedID: String?
    @State private var filter = ""
    @State private var sample = ColorsPreview.Sample.plsql
    @State private var renaming: SyntaxScheme?
    @State private var newName = ""

    private var settings: PelikanWorkspace.Settings { workspace.settings }
    private var selected: SyntaxScheme? {
        let id = selectedID ?? settings.activeSyntaxScheme(dark: NSApp.effectiveAppearance.isDark).id
        return settings.syntaxSchemes.first { $0.id == id }
    }
    private var customIndex: Int? { selected.flatMap { s in settings.customSyntaxSchemes.firstIndex { $0.id == s.id } } }

    private func visible(dark: Bool) -> [SyntaxScheme] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        return settings.syntaxSchemes.filter { $0.isDark == dark && (q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) || $0.author.localizedCaseInsensitiveContains(q)) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                TextField(L10n.tr("Filtruj motywy"), text: $filter).textFieldStyle(.roundedBorder)
                List(selection: $selectedID) {
                    Section(L10n.tr("Jasne")) { ForEach(visible(dark: false)) { row($0).tag(Optional($0.id)) } }
                    Section(L10n.tr("Ciemne")) { ForEach(visible(dark: true)) { row($0).tag(Optional($0.id)) } }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: false))
                // Kliknięcie motywu włącza go od razu w trybie, w którym jest teraz system (podgląd na żywo w edytorach);
                // drugi tryb — przyciskami „Użyj w trybie…”.
                .onChange(of: selectedID) { _, id in
                    guard let id else { return }
                    if NSApp.effectiveAppearance.isDark { workspace.settings.syntaxSchemeDark = id } else { workspace.settings.syntaxSchemeLight = id }
                }
                HStack {
                    Button(L10n.tr("Importuj…")) { workspace.perform("editor.syntaxScheme.import") }
                        .help(L10n.tr("Motyw z pliku: Pelikan .json, base16/base24 .yaml, Xcode .xccolortheme, TextMate .tmTheme, Visual Studio Code .json"))
                    Spacer()
                    if let s = selected {
                        Button(L10n.tr("Eksportuj…")) { workspace.perform("editor.syntaxScheme.export", CommandArguments(["scheme": .string(s.id)])) }
                    }
                }
                .controlSize(.small)
            }
            .frame(width: 270)
            if let s = selected { detail(s) } else { Spacer() }
        }
        .padding(12)
        .sheet(item: $renaming) { s in
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.tr("Zapisz jako własny")).font(.headline)
                TextField(L10n.tr("Nazwa"), text: $newName).frame(width: 300)
                HStack {
                    Spacer()
                    Button(L10n.tr("Anuluj")) { renaming = nil }.keyboardShortcut(.cancelAction)
                    Button(L10n.tr("Zapisz")) {
                        let copy = s.copy(named: newName.trimmingCharacters(in: .whitespaces).isEmpty ? L10n.tr("\(s.name) (kopia)") : newName)
                        workspace.settings.customSyntaxSchemes.append(copy)
                        selectedID = copy.id
                        renaming = nil
                    }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
    }

    private func row(_ s: SyntaxScheme) -> some View {
        HStack(spacing: 6) {
            ColorsPreview.swatch(s)
            Text(s.name).lineLimit(1)
            Spacer()
            if !s.isBuiltin { Text(L10n.tr("własny")).font(.uiSecondary).foregroundStyle(.secondary) }
            if settings.syntaxSchemeLight == s.id || settings.syntaxSchemeDark == s.id {
                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                    .help(L10n.tr("Motyw w użyciu"))
            }
        }
    }

    @ViewBuilder
    private func detail(_ s: SyntaxScheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.name).font(.title3.weight(.semibold))
                Text(s.isDark ? L10n.tr("ciemny") : L10n.tr("jasny")).foregroundStyle(.secondary)
                Spacer()
            }
            let credit = [s.author, s.source == "tinted-theming" ? L10n.tr("paleta z tinted-theming (MIT)") : s.source].filter { !$0.isEmpty }.joined(separator: " · ")
            if !credit.isEmpty { Text(credit).font(.uiSecondary).foregroundStyle(.secondary).lineLimit(1) }
            HStack {
                Button(L10n.tr("Użyj w trybie jasnym")) { workspace.settings.syntaxSchemeLight = s.id }
                    .disabled(settings.syntaxSchemeLight == s.id)
                Button(L10n.tr("Użyj w trybie ciemnym")) { workspace.settings.syntaxSchemeDark = s.id }
                    .disabled(settings.syntaxSchemeDark == s.id)
                Spacer()
                Button(L10n.tr("Zapisz jako własny…")) { newName = L10n.tr("\(s.name) (kopia)"); renaming = s }
                if !s.isBuiltin {
                    Button(L10n.tr("Usuń"), role: .destructive) {
                        workspace.perform("editor.syntaxScheme.delete", CommandArguments(["scheme": .string(s.id)]))
                        selectedID = nil
                    }
                }
            }
            .controlSize(.small)
            Text(L10n.tr("W trybie jasnym: \(settings.activeSyntaxScheme(dark: false).name) · w trybie ciemnym: \(settings.activeSyntaxScheme(dark: true).name)"))
                .font(.uiSecondary).foregroundStyle(.secondary)
            Text(NSApp.effectiveAppearance.isDark
                 ? L10n.tr("System jest teraz w trybie ciemnym — kliknięty motyw działa od razu w trybie ciemnym.")
                 : L10n.tr("System jest teraz w trybie jasnym — kliknięty motyw działa od razu w trybie jasnym."))
                .font(.uiSecondary).foregroundStyle(.secondary)
            if !settings.editorColors.isSystem {
                Label(L10n.tr("Własny kolor tekstu lub tła z karty Edytor › Kolory czcionek przesłania motyw — przycisk Systemowe tam go usuwa."),
                      systemImage: "exclamationmark.triangle")
                    .font(.uiSecondary).foregroundStyle(.orange)
            }
            Picker("", selection: $sample) {
                ForEach(ColorsPreview.Sample.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 320)
            ColorsPreview(scheme: s, sample: sample).frame(height: 190)
            if let i = customIndex {
                editor(i)
            } else {
                Text(L10n.tr("Motyw wbudowany jest tylko do odczytu — aby zmienić kolory, zapisz go jako własny."))
                    .font(.uiSecondary).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: Edycja motywu własnego

    private func scheme(_ i: Int) -> Binding<SyntaxScheme> {
        // Indeks sprawdzany przy każdym dostępie — po usunięciu motywu widok bywa jeszcze raz liczony ze starym indeksem.
        Binding(get: { workspace.settings.customSyntaxSchemes.indices.contains(i) ? workspace.settings.customSyntaxSchemes[i] : .pelikanLight },
                set: { if workspace.settings.customSyntaxSchemes.indices.contains(i) { workspace.settings.customSyntaxSchemes[i] = $0 } })
    }

    private func editor(_ i: Int) -> some View {
        let s = scheme(i)
        return ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField(L10n.tr("Nazwa"), text: s.name).frame(width: 220)
                    Toggle(L10n.tr("Motyw ciemny"), isOn: s.isDark)
                        .help(L10n.tr("Na liście w grupie ciemnych; wybór dla trybu jasnego i ciemnego jest niezależny"))
                }
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow {
                        Text(L10n.tr("Kategoria")).foregroundStyle(.secondary)
                        Text(L10n.tr("Kolor")).foregroundStyle(.secondary)
                        Text(L10n.tr("Pogrubienie")).foregroundStyle(.secondary)
                        Text(L10n.tr("Kursywa")).foregroundStyle(.secondary)
                    }
                    ForEach(SyntaxStyle.allCases, id: \.self) { style in
                        GridRow {
                            Text(style.title)
                            colorWell(s, tokenColor(s, style), fallback: fallback(s.wrappedValue, style))
                            Toggle("", isOn: tokenFlag(s, style, \.bold)).labelsHidden()
                            Toggle("", isOn: tokenFlag(s, style, \.italic)).labelsHidden()
                        }
                    }
                    Divider().gridCellColumns(4)
                    ForEach(Self.editorParts, id: \.title) { part in
                        GridRow {
                            Text(part.title)
                            colorWell(s, s[dynamicMember: part.path], fallback: ColorsPreview.system(part.system, dark: s.wrappedValue.isDark))
                            Color.clear.frame(width: 1, height: 1)
                            Color.clear.frame(width: 1, height: 1)
                        }
                    }
                }
                .font(.uiSecondary)
            }
        }
    }

    static let editorParts: [(title: String, path: WritableKeyPath<SyntaxScheme, RGB?>, system: NSColor)] = [
        (L10n.tr("Tło"), \.background, .textBackgroundColor), (L10n.tr("Tekst"), \.text, .textColor),
        (L10n.tr("Zaznaczenie"), \.selection, .selectedTextBackgroundColor), (L10n.tr("Linia bieżąca"), \.currentLine, .quaternaryLabelColor),
        (L10n.tr("Numery linii"), \.lineNumber, .tertiaryLabelColor), (L10n.tr("Kursor"), \.cursor, .textColor),
    ]

    private func fallback(_ s: SyntaxScheme, _ style: SyntaxStyle) -> RGB {
        s.style(style).color ?? s.text ?? ColorsPreview.system(.textColor, dark: s.isDark)
    }

    private func tokenColor(_ s: Binding<SyntaxScheme>, _ style: SyntaxStyle) -> Binding<RGB?> {
        Binding(get: { s.wrappedValue.styles[style]?.color },
                set: { c in var t = s.wrappedValue.style(style); t.color = c; s.wrappedValue.styles[style] = t })
    }

    private func tokenFlag(_ s: Binding<SyntaxScheme>, _ style: SyntaxStyle, _ flag: WritableKeyPath<TokenStyle, Bool>) -> Binding<Bool> {
        Binding(get: { s.wrappedValue.style(style)[keyPath: flag] },
                set: { v in var t = s.wrappedValue.style(style); t[keyPath: flag] = v; s.wrappedValue.styles[style] = t })
    }

    /// Pole koloru; przycisk ↺ — kolor systemu (tło, tekst) albo zwykłego tekstu (kategorie).
    private func colorWell(_ s: Binding<SyntaxScheme>, _ value: Binding<RGB?>, fallback: RGB) -> some View {
        HStack(spacing: 4) {
            ColorPicker("", selection: Binding(
                get: { Color(nsColor: SyntaxTheme.ns(value.wrappedValue ?? fallback)) },
                set: { c in
                    let n = NSColor(c).usingColorSpace(.sRGB) ?? .black
                    value.wrappedValue = RGB(red: Double(n.redComponent), green: Double(n.greenComponent), blue: Double(n.blueComponent))
                }), supportsOpacity: false).labelsHidden()
            Button { value.wrappedValue = nil } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.borderless).disabled(value.wrappedValue == nil)
                .iconLabel(L10n.tr("Kolor domyślny (systemu albo zwykłego tekstu)"))
        }
    }
}

/// Podgląd motywu (niezależny od motywu w użyciu): przykład SQL, PL/SQL albo Pro*C kolorowany kolorami motywu.
struct ColorsPreview: NSViewRepresentable {
    enum Sample: CaseIterable {
        case sql, plsql, proC
        var title: String {
            switch self {
            case .sql: "SQL"
            case .plsql: "PL/SQL"
            case .proC: "Pro*C"
            }
        }
        var code: String {
            switch self {
            case .sql:
                """
                -- \(L10n.tr("Pracownicy z pensją powyżej średniej działu"))
                select /*+ index(e emp_dept_ix) */ e.ename, d."Nazwa działu",
                       to_char(e.hiredate, 'YYYY-MM-DD') as hired, nvl(e.comm, 0) + 100.5 as bonus
                  from emp e join dept d on d.deptno = e.deptno
                 where e.sal > (select avg(sal) from emp where deptno = :dept)
                   and e.job in ('CLERK', 'ANALYST') and e.ename like '&prefix%';
                """
            case .plsql:
                """
                create or replace package body pel_emp_api as
                  /* \(L10n.tr("Podwyżka z kontrolą limitu")) */
                  procedure raise_salary(p_empno in number, p_pct in number default 5) is
                    v_sal emp.sal%type;
                  begin
                    $if $$debug $then dbms_output.put_line('debug'); $end
                    select sal into v_sal from emp where empno = p_empno for update;
                    update emp set sal = round(v_sal * (1 + p_pct / 100), 2) where empno = p_empno;
                  exception
                    when no_data_found then raise_application_error(-20001, 'Brak ' || p_empno);
                  end raise_salary;
                end pel_emp_api;
                """
            case .proC:
                """
                #include <stdio.h>
                EXEC SQL INCLUDE SQLCA;
                int main(void) {
                    VARCHAR ename[20];   /* \(L10n.tr("zmienna hosta")) */
                    int empno = 7839;
                    EXEC SQL SELECT ename INTO :ename FROM emp WHERE empno = :empno;
                    EXEC SQL EXECUTE
                      BEGIN dbms_output.put_line('ok'); END;
                    END-EXEC;
                    printf("%.*s\\n", ename.len, ename.arr);
                    return sqlca.sqlcode;
                }
                """
            }
        }
    }

    let scheme: SyntaxScheme
    let sample: Sample

    /// Kolor systemu w trybie jasnym albo ciemnym (motywy bez własnego tła).
    static func system(_ c: NSColor, dark: Bool) -> RGB {
        var out = RGB(0, 0, 0)
        (NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
            if let n = c.usingColorSpace(.sRGB) { out = RGB(red: Double(n.redComponent), green: Double(n.greenComponent), blue: Double(n.blueComponent)) }
        }
        return out
    }

    /// Próbka na liście: tło z trzema kolorami (słowo kluczowe, napis, komentarz).
    static func swatch(_ s: SyntaxScheme) -> some View {
        let bg = s.background ?? system(.textBackgroundColor, dark: s.isDark)
        let fg = s.text ?? system(.textColor, dark: s.isDark)
        return HStack(spacing: 2) {
            ForEach([SyntaxStyle.keyword, .string, .comment], id: \.self) { st in
                Circle().fill(Color(nsColor: SyntaxTheme.ns(s.style(st).color ?? fg))).frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 3)
        .background(Color(nsColor: SyntaxTheme.ns(bg)), in: RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.secondary.opacity(0.4), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    static func attributed(_ code: String, scheme s: SyntaxScheme, font: NSFont, proC: Bool) -> NSAttributedString {
        let fg = s.text ?? system(.textColor, dark: s.isDark)
        let out = NSMutableAttributedString(string: code, attributes: [.font: font, .foregroundColor: SyntaxTheme.ns(s.style(.plain).color ?? fg)])
        let text = Array(code.utf16)
        func apply(_ style: SyntaxStyle, _ r: NSRange) {
            let t = s.style(style)
            let color = t.color ?? (style == .operator && s.text == nil ? system(.secondaryLabelColor, dark: s.isDark) : fg)
            out.addAttribute(.foregroundColor, value: SyntaxTheme.ns(color), range: r)
            var f = font
            if t.bold { f = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask) }
            if t.italic { f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask) }
            if f != font { out.addAttribute(.font, value: f, range: r) }
        }
        if proC {
            for sp in ProCLexer.spans(text) { apply(sp.style, NSRange(location: sp.start, length: sp.length)) }
        } else {
            for t in Lexer(utf16: text).tokenize() {
                if let st = SyntaxClassifier.style(t, in: text) { apply(st, NSRange(location: t.start, length: t.length)) }
            }
        }
        return out
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        if let tv = scroll.documentView as? NSTextView {
            tv.isEditable = false
            tv.isSelectable = true
            tv.textContainerInset = NSSize(width: 6, height: 6)
            tv.setAccessibilityLabel(L10n.tr("Podgląd motywu"))
        }
        scroll.borderType = .bezelBorder
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        let font = InterfaceFonts.shared.code
        tv.textStorage?.setAttributedString(Self.attributed(sample.code, scheme: scheme, font: font, proC: sample == .proC))
        let bg = SyntaxTheme.ns(scheme.background ?? Self.system(.textBackgroundColor, dark: scheme.isDark))
        tv.backgroundColor = bg
        scroll.backgroundColor = bg
        tv.selectedTextAttributes = [.backgroundColor: SyntaxTheme.ns(scheme.selection ?? Self.system(.selectedTextBackgroundColor, dark: scheme.isDark))]
    }
}

import PelikanSQL
import PelikanWorkspace
import SwiftUI

/// Reguły formatera PL/SQL z podglądem na żywo (UG 29.1–29.2) i formatowanie automatyczne (UG 29.4).
struct BeautifierPane: View {
    let workspace: Workspace
    @State private var specialCase = ""

    static let sample = """
        create or replace procedure podwyzka(p_dzial in number, p_procent number default 10) is
        cursor c is select empno, sal from emp where deptno = p_dzial;
        begin
        for r in c loop
        if r.sal < 1000 then update emp set sal = sal * (1 + p_procent / 100), comm = 0 where empno = r.empno;
        elsif r.sal is null then null; end if;
        end loop;
        dbms_output.put_line('Gotowe');
        exception when others then raise;
        end;
        /
        """

    private var preview: String {
        (try? Beautifier.format(Self.sample, options: workspace.settings.beautifier)) ?? Self.sample
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Form {
                Section(L10n.tr("Układ")) {
                    Stepper(value: setting(workspace, \.beautifier.indent), in: 1...8) {
                        Text(L10n.tr("Wcięcie: \(workspace.settings.beautifier.indent)"))
                    }
                    Toggle(L10n.tr("Wcięcie znakami tabulacji"), isOn: setting(workspace, \.beautifier.useTabs))
                    Stepper(value: setting(workspace, \.beautifier.rightMargin), in: 40...250, step: 10) {
                        Text(L10n.tr("Prawy margines: \(workspace.settings.beautifier.rightMargin)"))
                    }
                    Picker(L10n.tr("Listy (SELECT, SET, ORDER BY)"), selection: setting(workspace, \.beautifier.listLayout)) {
                        Text(L10n.tr("Element w linii")).tag(BeautifierOptions.ListLayout.onePerLine)
                        Text(L10n.tr("Do marginesu")).tag(BeautifierOptions.ListLayout.fit)
                    }
                    Toggle(L10n.tr("Przecinek na początku linii"), isOn: setting(workspace, \.beautifier.commaBefore))
                    Toggle(L10n.tr("Zachowuj puste linie"), isOn: setting(workspace, \.beautifier.keepBlankLines))
                }
                Section(L10n.tr("Wielkość liter")) {
                    Picker(L10n.tr("Słowa kluczowe"), selection: setting(workspace, \.beautifier.keywordCase)) { caseOptions }
                    Picker(L10n.tr("Identyfikatory"), selection: setting(workspace, \.beautifier.identifierCase)) { caseOptions }
                    TextField(L10n.tr("Pisownia specjalna (po przecinku)"), text: $specialCase, prompt: Text("DBMS_Output, UTL_File"))
                        .onSubmit(saveSpecialCase)
                }
                Section(L10n.tr("Formatuj automatycznie")) {
                    Toggle(L10n.tr("Po otwarciu źródła z bazy"), isOn: setting(workspace, \.beautifier.afterLoad))
                    Toggle(L10n.tr("Przed kompilacją"), isOn: setting(workspace, \.beautifier.beforeCompile))
                    Toggle(L10n.tr("Przed zapisem do pliku"), isOn: setting(workspace, \.beautifier.beforeSave))
                }
            }
            .formStyle(.grouped)
            .frame(width: 360)
            ScrollView([.vertical, .horizontal]) {
                Text(preview)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .accessibilityLabel(L10n.tr("Podgląd formatowania"))
        }
        .onAppear { specialCase = workspace.settings.beautifier.specialCase.joined(separator: ", ") }
        .onDisappear(perform: saveSpecialCase)
    }

    @ViewBuilder private var caseOptions: some View {
        Text(L10n.tr("Bez zmian")).tag(BeautifierOptions.WordCase.unchanged)
        Text(L10n.tr("WIELKIE")).tag(BeautifierOptions.WordCase.upper)
        Text(L10n.tr("małe")).tag(BeautifierOptions.WordCase.lower)
        Text(L10n.tr("Pierwsza wielka")).tag(BeautifierOptions.WordCase.initCap)
    }

    private func saveSpecialCase() {
        workspace.settings.beautifier.specialCase = specialCase.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

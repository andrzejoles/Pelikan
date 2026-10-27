import AppKit
import PelikanLog
import PelikanWorkspace
import SwiftUI

/// Okno zgłoszenia problemu (PL-INFRA-013, D173): tytuł, opis, wybór dołączanych części i podgląd dokładnej treści.
/// „Otwórz zgłoszenie na GitHubie” kopiuje treść do schowka i otwiera stronę nowego zgłoszenia z wypełnionymi polami —
/// wysyła je użytkownik ze swojego konta.
struct ProblemReportView: View {
    let workspace: Workspace
    let repository: String
    @State var report: ProblemReport
    let close: () -> Void
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(L10n.tr("Zgłoszenie trafi do publicznego repozytorium na GitHubie i będzie widoczne dla wszystkich. Nie wpisuj haseł, nazw baz, adresów serwerów ani danych. Przed wysłaniem zobaczysz je jeszcze na stronie GitHuba."))
                    .font(.ui)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            TextField(L10n.tr("Tytuł"), text: $report.title)
            Text(L10n.tr("Co się stało? Co robiłeś i czego się spodziewałeś?")).font(.uiHeadline)
            TextEditor(text: $report.details)
                .font(.ui)
                .frame(minHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            if case .error = report.origin {
                Toggle(L10n.tr("Dołącz komunikat błędu (może zawierać nazwy obiektów, schematów i dane — sprawdź i popraw poniżej)"), isOn: $report.includeErrorMessage)
                if report.includeErrorMessage {
                    TextEditor(text: $report.errorMessage)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 50, maxHeight: 90)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                }
            }
            Toggle(L10n.tr("Dołącz opis środowiska (wersja, system, sterowniki — bez nazw połączeń)"), isOn: $report.includeEnvironment)
            Toggle(L10n.tr("Dołącz ostatnie wpisy dziennika (\(report.logTail.count))"), isOn: $report.includeLog)
                .disabled(report.logTail.isEmpty)
            Text(L10n.tr("Podgląd treści")).font(.uiHeadline)
            ScrollView {
                Text(report.body())
                    .font(.code)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            HStack {
                Button(L10n.tr("Eksportuj pełny dziennik…")) { workspace.perform("help.exportLog") }
                Spacer()
                if !message.isEmpty { Text(message).font(.uiSecondary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                Button(L10n.tr("Anuluj"), action: close).keyboardShortcut(.cancelAction)
                Button(L10n.tr("Kopiuj treść")) {
                    copy()
                    message = L10n.tr("Skopiowano do schowka")
                }
                Button(L10n.tr("Otwórz zgłoszenie na GitHubie"), action: send)
                    .keyboardShortcut(.defaultAction)
                    .disabled(report.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(minWidth: 640, minHeight: 560)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.body(), forType: .string)
    }

    private func send() {
        copy()
        guard let (url, truncated) = report.issueURL(repository: repository) else { return }
        Log.app.info("Otwarto stronę nowego zgłoszenia problemu (treść skrócona: \(truncated))")
        NSWorkspace.shared.open(url)
        if truncated {
            message = L10n.tr("Treść była za długa dla adresu — pełna jest w schowku: na stronie zgłoszenia zaznacz opis i wklej (⌘V).")
        } else {
            close()
        }
    }
}

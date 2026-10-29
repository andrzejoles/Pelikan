import Foundation

/// Czynność okna celów SSH (zdalny build Pro*C, Etap P).
public enum SSHTargetAction: Sendable, Equatable {
    /// Menedżer celów (drzewo z folderami, dodaj/edytuj/duplikuj/usuń).
    case manage
    /// „Testuj” dla celu o nazwie (nil — zaznaczony w menedżerze).
    case test(String?)
    /// Eksport / import listy celów (bez sekretów).
    case export
    case `import`
}

/// Czynność wdrożenia Pro*C (pipeline, konsola, historia, blokada, lokalny git).
public enum ProCDeployAction: Sendable, Equatable {
    /// Wdrożenie na cel (nil — wybór w oknie): podsumowanie, potwierdzenie PROD, konsola.
    case deploy(String?)
    /// Wycofanie binarki z `.prev` albo z kopii.
    case rollback(String?)
    /// Historia wdrożeń (lokalna i z serwera) z logami.
    case history
    /// Konsola bieżącego/ostatniego wdrożenia.
    case console
    /// Zatrzymanie bieżącego wdrożenia (Stop).
    case stop
    /// Ręczne zdjęcie blokady celu (po potwierdzeniu).
    case releaseLock(String?)
    /// Stan lokalnego repo i commity wdrożone na celach („gdzie co jest”).
    case gitStatus
}

/// Cele SSH zdalnego builda Pro*C (zadanie Pro*C, „Menedżer połączeń SSH”). Tylko dla użytkownika (agent — Brak):
/// cele zawierają hosty i ścieżki serwera, a operacje na serwerze należą do pipeline'u z potwierdzeniami.
@MainActor
enum RemoteTargetCommands {
    static func command(_ id: CommandID, _ title: String, params: [CommandParameter] = [], effect: CommandEffect, summary: String,
                        feature: String, _ run: @escaping CommandHandler) -> Command {
        Command(CommandDescriptor(id: id, title: title, category: .tools, submenu: L10n.tr("Zdalny build Pro*C"), parameters: params,
                                  agent: .none, effect: effect, summary: summary, feature: feature), run: run)
    }

    static var all: [Command] {
        [
            command("ssh.manager", L10n.tr("Cele SSH…"), effect: .uiState,
                    summary: L10n.tr("Pokazuje menedżer celów SSH zdalnego builda Pro*C: drzewo z folderami, dodawanie, edycja, duplikowanie i usuwanie celów, środowisko UAT/PROD."),
                    feature: "PC-CONN-002") { ctx in
                ctx.ui?.showSSHTargets(.manage)
                return .ok
            },
            command("ssh.test", L10n.tr("Testuj cel SSH"), params: [CommandParameter("target", .string, L10n.tr("Nazwa celu (domyślnie zaznaczony)"))],
                    effect: .external,
                    summary: L10n.tr("Łączy się z serwerem celu i sprawdza system, wersję serwera SSH, make, git, gałąź i czystość kopii roboczej, compress/gzip oraz katalogi bazowy, src, bin i kopii zapasowych (tylko odczyt; katalog kopii zapasowych tworzony po potwierdzeniu)."),
                    feature: "PC-CONN-003") { ctx in
                ctx.ui?.showSSHTargets(.test(ctx.arguments.string("target")))
                return .ok
            },
            command("ssh.export", L10n.tr("Eksportuj cele SSH…"), effect: .external,
                    summary: L10n.tr("Zapisuje listę celów SSH i folderów do pliku JSON — bez haseł (sekrety zostają w Pęku kluczy)."),
                    feature: "PC-CONN-001") { ctx in
                ctx.ui?.showSSHTargets(.export)
                return .ok
            },
            command("proc.deploy", L10n.tr("Wdróż na cel…"), params: [CommandParameter("target", .string, L10n.tr("Nazwa celu (domyślnie wybór w oknie)"))],
                    effect: .external,
                    summary: L10n.tr("Wdrożenie Pro*C: podsumowanie zmian (commit na serwerze → remote), dla PROD potwierdzenie nazwą celu, potem na serwerze blokada, kontrola kopii roboczej, git pull --ff-only, kopia zapasowa binarek, make, instalacja do bin i historia — z konsolą na żywo."),
                    feature: "PC-DEPLOY-001") { ctx in
                ctx.ui?.showProCDeploy(.deploy(ctx.arguments.string("target")))
                return .ok
            },
            command("proc.rollback", L10n.tr("Wycofaj binarkę…"), params: [CommandParameter("target", .string, L10n.tr("Nazwa celu"))],
                    effect: .external,
                    summary: L10n.tr("Przywraca binarkę na celu z wersji .prev albo z wybranej kopii w katalogu kopii zapasowych (po potwierdzeniu; PROD — nazwą celu). Źródła wycofuje się przez revert w git."),
                    feature: "PC-DEPLOY-003") { ctx in
                ctx.ui?.showProCDeploy(.rollback(ctx.arguments.string("target")))
                return .ok
            },
            command("proc.history", L10n.tr("Historia wdrożeń"), effect: .uiState,
                    summary: L10n.tr("Historia wdrożeń i wycofań: lokalna (z pełnymi logami) i z serwera celu."),
                    feature: "PC-DEPLOY-004") { ctx in
                ctx.ui?.showProCDeploy(.history)
                return .ok
            },
            command("proc.console", L10n.tr("Konsola wdrożenia"), effect: .uiState,
                    summary: L10n.tr("Konsola wdrożenia: sekcje kroków ze statusem i czasem, filtr błędów, klikalne błędy proc/xlc, Stop, zapis logu."),
                    feature: "PC-CONS-001") { ctx in
                ctx.ui?.showProCDeploy(.console)
                return .ok
            },
            command("proc.stop", L10n.tr("Zatrzymaj wdrożenie"), effect: .external,
                    summary: L10n.tr("Stop: kończy ssh -tt (SIGHUP po stronie serwera) i zapasowo zabija grupę procesów skryptu; blokada zdejmowana."),
                    feature: "PC-CONS-002") { ctx in
                ctx.ui?.showProCDeploy(.stop)
                return .ok
            },
            command("proc.releaseLock", L10n.tr("Zdejmij blokadę celu…"), params: [CommandParameter("target", .string, L10n.tr("Nazwa celu"))],
                    effect: .external,
                    summary: L10n.tr("Ręczne zdjęcie blokady wdrożenia na serwerze (np. po awarii) — pokazuje, kto ją trzyma, i wymaga potwierdzenia."),
                    feature: "PC-DEPLOY-002") { ctx in
                ctx.ui?.showProCDeploy(.releaseLock(ctx.arguments.string("target")))
                return .ok
            },
            command("proc.gitStatus", L10n.tr("Stan git i wdrożeń"), effect: .uiState,
                    summary: L10n.tr("Lokalne repo projektu: gałąź, niezatwierdzone zmiany, commity niewypchnięte; commit remote i commit wdrożony na każdym celu."),
                    feature: "PC-GIT-001") { ctx in
                ctx.ui?.showProCDeploy(.gitStatus)
                return .ok
            },
            command("ssh.import", L10n.tr("Importuj cele SSH…"), effect: .settings,
                    summary: L10n.tr("Dołącza cele SSH i foldery z pliku JSON (nowe identyfikatory; hasła trzeba podać ponownie)."),
                    feature: "PC-CONN-001") { ctx in
                ctx.ui?.showSSHTargets(.import)
                return .ok
            },
        ]
    }
}

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
                    summary: L10n.tr("Łączy się z serwerem celu i sprawdza system, wersję serwera SSH, make, git, gałąź i czystość working copy, compress/gzip oraz katalogi bazowy, src, bin i backupów (tylko odczyt; katalog backupów tworzony po potwierdzeniu)."),
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
            command("ssh.import", L10n.tr("Importuj cele SSH…"), effect: .settings,
                    summary: L10n.tr("Dołącza cele SSH i foldery z pliku JSON (nowe identyfikatory; hasła trzeba podać ponownie)."),
                    feature: "PC-CONN-001") { ctx in
                ctx.ui?.showSSHTargets(.import)
                return .ok
            },
        ]
    }
}

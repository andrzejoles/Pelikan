import AppKit
import PelikanWorkspace
import SwiftUI

/// Okno debugera (UG 5.10): przyciski Start/Kontynuuj/Wejdź/Przejdź/Wyjdź/Do wyjątku/Zatrzymaj, miejsce zatrzymania,
/// stos wywołań (klik = zmienne ramki) i zmienne z rozwijanymi rekordami i kolekcjami.
struct DebuggerPanel: View {
    let workspace: Workspace
    @Bindable var debugger: DebuggerEngine
    let document: PelikanWorkspace.Document
    @State private var newWatch = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolbar
            Text(status).font(.ui).foregroundStyle(.secondary).lineLimit(2)
            HSplitView {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("Stos wywołań")).font(.uiSecondary.bold())
                    List(Array(debugger.stack.enumerated()), id: \.offset) { i, f in
                        Button { Task { await debugger.selectFrame(i) } } label: {
                            HStack {
                                Image(systemName: i == debugger.selectedFrame ? "arrowtriangle.right.fill" : "circle").font(.uiSecondary)
                                Text(f.isTestBlock ? L10n.tr("Blok testu") : "\(f.owner).\(f.name)").font(.code)
                                Spacer()
                                Text("\(f.line)").foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minWidth: 200)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("Zmienne")).font(.uiSecondary.bold())
                    List(debugger.variables, children: \.children) { v in variableRow(v) }
                    Text(L10n.tr("Obserwowane")).font(.uiSecondary.bold())
                    List(debugger.watchValues, children: \.children) { v in
                        variableRow(v).contextMenu {
                            Button(L10n.tr("Usuń z obserwowanych")) { debugger.removeWatch(v.path) }
                        }
                    }
                    .frame(minHeight: 70)
                    HStack {
                        TextField(L10n.tr("Wyrażenie do obserwowania (np. v, r.pole, t(3))"), text: $newWatch)
                            .onSubmit { addWatch() }
                        Button { addWatch() } label: { Image(systemName: "plus") }.iconLabel(L10n.tr("Dodaj")).disabled(newWatch.isEmpty)
                    }
                }
                .frame(minWidth: 260)
            }
        }
        .padding(10)
        .frame(minWidth: 560, minHeight: 320)
    }

    private func addWatch() {
        let w = newWatch
        newWatch = ""
        Task { await debugger.addWatch(w) }
    }

    /// Wiersz zmiennej z menu: Ustaw wartość (SET_VALUE, tylko skalary), Kopiuj, Obserwuj (UG 5.10).
    private func variableRow(_ v: DebugVariable) -> some View {
        HStack {
            Text(v.name).font(.code)
            Spacer()
            Text(v.value).font(.code).foregroundStyle(v.children == nil ? .primary : .secondary)
                .textSelection(.enabled)
        }
        .contextMenu {
            if v.children == nil {
                Button(L10n.tr("Ustaw wartość…")) {
                    Task {
                        guard let value = await workspace.ui?.askText(L10n.tr("Nowa wartość \(v.name)"), message: L10n.tr("Literał PL/SQL albo tekst; NULL — wartość pusta."),
                                                                   defaultValue: v.value) else { return }
                        do { try await debugger.setValue(v.path, to: value) } catch { workspace.ui?.showError(error.localizedDescription) }
                    }
                }.disabled(debugger.state != .paused)
            }
            Button(L10n.tr("Kopiuj wartość")) { workspace.ui?.copyToClipboard(v.value, html: nil) }
            Button(L10n.tr("Obserwuj")) { Task { await debugger.addWatch(v.path) } }
        }
    }

    private var status: String {
        switch debugger.state {
        case .idle:
            // Skrót z bieżącej mapy klawiszy (profil, własne skróty), nie zaszyty w tekście.
            if let chord = workspace.keymap.chords(for: "debug.start").first {
                L10n.tr("Gotowy — \(chord.displayString) uruchamia skrypt okna testu z debugerem")
            } else {
                L10n.tr("Gotowy — „\(help("debug.start"))” uruchamia skrypt okna testu z debugerem")
            }
        case .running: L10n.tr("Wykonywanie…")
        case .paused:
            debugger.location.map { $0.isTestBlock ? L10n.tr("Zatrzymano: blok testu, linia \($0.line)") : L10n.tr("Zatrzymano: \($0.owner).\($0.name), linia \($0.line)") } ?? ""
        case .finished: debugger.message ?? L10n.tr("Zakończono")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            button("play.fill", "debug.start", enabled: debugger.state != .paused && debugger.state != .running)
            Divider().frame(height: 18)
            button("forward.end.fill", "debug.run")
            button("arrow.down.to.line", "debug.stepInto")
            button("arrow.turn.down.right", "debug.stepOver")
            button("arrow.up.to.line", "debug.stepOut")
            button("exclamationmark.triangle", "debug.runToException")
            Divider().frame(height: 18)
            button("stop.fill", "debug.stop", enabled: debugger.state == .paused || debugger.state == .running)
            // SQL / PL/SQL w sesji debugowanej (DBMS_DEBUG.EXECUTE) — komenda rejestru ze strażnikiem zmian (APP2-06).
            button("terminal", "debug.executeInTarget")
            Spacer()
            if debugger.state == .running { ProgressView().controlSize(.small) }
        }
    }

    /// Podpowiedź: tytuł komendy z rejestru i skrót z bieżącej mapy klawiszy (profil, własne skróty) — jak na wstążce (R4-19).
    private func help(_ command: CommandID) -> String {
        let title = workspace.registry.command(command)?.descriptor.title ?? command.rawValue
        guard let chord = workspace.keymap.chords(for: command).first else { return title }
        return "\(title) (\(chord.displayString))"
    }

    private func button(_ symbol: String, _ command: String, enabled: Bool? = nil) -> some View {
        Button {
            // Komendy debugera działają na aktywnym oknie testu — najpierw okno tego debugera.
            workspace.activate(document.id)
            workspace.perform(CommandID(rawValue: command))
        } label: { Image(systemName: symbol) }
        .iconLabel(help(CommandID(rawValue: command)))
        .disabled(!(enabled ?? (debugger.state == .paused)))
    }
}

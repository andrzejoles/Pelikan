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
            Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            HSplitView {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("Stos wywołań")).font(.caption.bold())
                    List(Array(debugger.stack.enumerated()), id: \.offset) { i, f in
                        Button { Task { await debugger.selectFrame(i) } } label: {
                            HStack {
                                Image(systemName: i == debugger.selectedFrame ? "arrowtriangle.right.fill" : "circle").font(.caption2)
                                Text(f.isTestBlock ? L10n.tr("Blok testu") : "\(f.owner).\(f.name)").font(.system(.body, design: .monospaced))
                                Spacer()
                                Text("\(f.line)").foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minWidth: 200)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("Zmienne")).font(.caption.bold())
                    List(debugger.variables, children: \.children) { v in variableRow(v) }
                    Text(L10n.tr("Obserwowane")).font(.caption.bold())
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

    /// SQL / PL/SQL w sesji debugowanej (DBMS_DEBUG.EXECUTE) — wynik w karcie Wyjście okna testu.
    private func executeInTarget() {
        Task {
            guard let sql = await workspace.ui?.askText(L10n.tr("Wykonaj w sesji debugowanej"), message: L10n.tr("Zapytanie (pierwsze 100 wierszy) albo blok PL/SQL."),
                                                        defaultValue: ""), !sql.isEmpty else { return }
            do {
                let lines = try await debugger.executeInTarget(sql)
                document.output.append("SQL> " + sql)
                document.output.append(contentsOf: lines)
            } catch { workspace.ui?.showError(error.localizedDescription) }
        }
    }

    private func addWatch() {
        let w = newWatch
        newWatch = ""
        Task { await debugger.addWatch(w) }
    }

    /// Wiersz zmiennej z menu: Ustaw wartość (SET_VALUE, tylko skalary), Kopiuj, Obserwuj (UG 5.10).
    private func variableRow(_ v: DebugVariable) -> some View {
        HStack {
            Text(v.name).font(.system(.body, design: .monospaced))
            Spacer()
            Text(v.value).font(.system(.body, design: .monospaced)).foregroundStyle(v.children == nil ? .primary : .secondary)
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
        case .idle: L10n.tr("Gotowy — Start (F9) uruchamia skrypt okna testu z debugerem")
        case .running: L10n.tr("Wykonywanie…")
        case .paused:
            debugger.location.map { $0.isTestBlock ? L10n.tr("Zatrzymano: blok testu, linia \($0.line)") : L10n.tr("Zatrzymano: \($0.owner).\($0.name), linia \($0.line)") } ?? ""
        case .finished: debugger.message ?? L10n.tr("Zakończono")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            button("play.fill", L10n.tr("Rozpocznij debugowanie (F9)"), "debug.start", enabled: debugger.state != .paused && debugger.state != .running)
            Divider().frame(height: 18)
            button("forward.end.fill", L10n.tr("Kontynuuj (⌃R)"), "debug.run")
            button("arrow.down.to.line", L10n.tr("Wejdź (⌃N)"), "debug.stepInto")
            button("arrow.turn.down.right", L10n.tr("Przejdź (⌃O)"), "debug.stepOver")
            button("arrow.up.to.line", L10n.tr("Wyjdź (⌃T)"), "debug.stepOut")
            button("exclamationmark.triangle", L10n.tr("Wykonaj do wyjątku"), "debug.runToException")
            Divider().frame(height: 18)
            button("stop.fill", L10n.tr("Zatrzymaj (⇧F9)"), "debug.stop", enabled: debugger.state == .paused || debugger.state == .running)
            Button { executeInTarget() } label: { Image(systemName: "terminal") }
                .iconLabel(L10n.tr("Wykonaj SQL w sesji debugowanej…")).disabled(debugger.state != .paused)
            Spacer()
            if debugger.state == .running { ProgressView().controlSize(.small) }
        }
    }

    private func button(_ symbol: String, _ help: String, _ command: String, enabled: Bool? = nil) -> some View {
        Button {
            // Komenda działa na oknie testu tego debugera (aktywuje je na czas startu).
            if command == "debug.start" { workspace.activate(document.id) }
            workspace.perform(CommandID(rawValue: command))
        } label: { Image(systemName: symbol) }
        .iconLabel(help)
        .disabled(!(enabled ?? (debugger.state == .paused)))
    }
}

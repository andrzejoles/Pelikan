import AppKit
import Charts
import PelikanWorkspace
import SwiftUI

/// Monitor zdarzeń (UG 24.13): alerty i rury, lista odebranych zdarzeń.
struct EventMonitorView: View {
    let workspace: Workspace
    @State private var connection: UUID?
    @State private var kind: EventMonitor.Kind = .alert
    @State private var names = ""
    @State private var monitor: EventMonitor?
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ToolConnectionPicker(workspace: workspace, connection: $connection).disabled(monitor?.running == true)
                Picker("", selection: $kind) {
                    Text("DBMS_ALERT").tag(EventMonitor.Kind.alert)
                    Text("DBMS_PIPE").tag(EventMonitor.Kind.pipe)
                }
                .pickerStyle(.segmented).frame(width: 220).disabled(monitor?.running == true)
                TextField(L10n.tr("Nazwy (po przecinku)"), text: $names).textFieldStyle(.roundedBorder).disabled(monitor?.running == true)
                if monitor?.running == true {
                    Button(L10n.tr("Zatrzymaj")) { Task { await monitor?.stop() } }
                } else {
                    Button(L10n.tr("Start")) { Task { await start() } }.disabled(names.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button(L10n.tr("Wyczyść")) { monitor?.clear() }
            }
            Table(monitor?.events ?? []) {
                TableColumn(L10n.tr("Czas")) { e in Text(e.time.formatted(date: .omitted, time: .standard)) }.width(90)
                TableColumn(L10n.tr("Nazwa")) { e in Text(e.name) }.width(160)
                TableColumn(L10n.tr("Treść")) { e in Text(e.message).textSelection(.enabled) }
            }
            Text(monitor?.error ?? message).font(.uiSecondary).foregroundStyle(monitor?.error == nil ? Color.secondary : Color.red)
        }
        .padding(10)
        .frame(minWidth: 620, minHeight: 360)
        .onDisappear { Task { await monitor?.stop() } }
    }

    init(workspace: Workspace) {
        self.workspace = workspace
        _connection = State(initialValue: workspace.toolConnection())
    }

    private func start() async {
        guard let conn = connection else { message = L10n.tr("Brak połączenia"); return }
        await monitor?.stop()
        let m = EventMonitor(kind: kind, names: names.split(separator: ",").map(String.init), connectionID: conn, in: workspace)
        do {
            try await m.start()
            monitor = m
            message = L10n.tr("Nasłuch: \(m.names.joined(separator: ", "))")
        } catch { message = error.localizedDescription }
    }
}

/// Test obciążenia (UG 24.17): kroki, wątki, iteracje; wyniki na żywo w tabeli, słupkach i linii przepustowości.
struct LoadTesterView: View {
    let workspace: Workspace
    @State private var connection: UUID?
    @State private var test: LoadTest = {
        var t = LoadTest()
        t.steps = [LoadStep(name: L10n.tr("Krok 1"), sql: "select count(*) from dual where :iteration > 0")]
        return t
    }()
    @State private var tester: LoadTester?
    @State private var selection: LoadStep.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ToolConnectionPicker(workspace: workspace, connection: $connection).disabled(tester?.running == true)
                Stepper(L10n.tr("Wątki: \(test.threads)"), value: $test.threads, in: 1...64)
                Stepper(L10n.tr("Iteracje: \(test.iterations)"), value: $test.iterations, in: 1...100_000)
                Toggle(L10n.tr("ROLLBACK po iteracji"), isOn: $test.rollback).toggleStyle(.checkbox)
                Spacer()
                if tester?.running == true {
                    Button(L10n.tr("Zatrzymaj")) { tester?.stop() }
                } else {
                    Button { start() } label: { Label(L10n.tr("Start"), systemImage: "play.fill") }.disabled(test.steps.isEmpty)
                }
                Button(L10n.tr("Zapisz do Excela…")) { export() }.disabled(tester == nil)
            }
            HSplitView {
                VStack(alignment: .leading) {
                    List(selection: $selection) {
                        ForEach($test.steps) { $s in
                            VStack(alignment: .leading) {
                                TextField(L10n.tr("Nazwa"), text: $s.name).font(.uiHeadline)
                                TextField("SQL", text: $s.sql, axis: .vertical).font(.system(size: 12, design: .monospaced)).lineLimit(1...5)
                            }
                            .tag(s.id)
                        }
                    }
                    HStack {
                        Button(L10n.tr("Dodaj krok")) { test.steps.append(LoadStep(name: L10n.tr("Krok \(test.steps.count + 1)"), sql: "")) }
                        Button(L10n.tr("Usuń")) { test.steps.removeAll { $0.id == selection } }.disabled(selection == nil)
                    }
                    Text(L10n.tr("Zmienne :thread i :iteration są wiązane automatycznie.")).font(.uiSecondary).foregroundStyle(.secondary)
                }
                .frame(minWidth: 320)
                results.frame(minWidth: 420)
            }
        }
        .padding(10)
        .frame(minWidth: 900, minHeight: 520)
        // Zamknięcie okna kończy test — inaczej wątki działałyby dalej na sesjach bez możliwości zatrzymania.
        .onDisappear { tester?.stop() }
    }

    init(workspace: Workspace) {
        self.workspace = workspace
        _connection = State(initialValue: workspace.toolConnection())
    }

    @ViewBuilder private var results: some View {
        if let t = tester {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("Iteracje: \(t.completedIterations) z \(test.threads * test.iterations)")).font(.uiSecondary)
                Table(t.stats) {
                    TableColumn(L10n.tr("Krok")) { s in Text(s.name) }
                    TableColumn(L10n.tr("Wykonania")) { s in Text("\(s.count)").monospacedDigit() }.width(80)
                    TableColumn(L10n.tr("Błędy")) { s in Text("\(s.errors)").foregroundStyle(s.errors > 0 ? .red : .primary) }.width(60)
                    TableColumn(L10n.tr("Średnio ms")) { s in Text(String(format: "%.1f", s.averageMs)).monospacedDigit() }.width(80)
                    TableColumn(L10n.tr("Maks ms")) { s in Text(String(format: "%.1f", s.maxMs)).monospacedDigit() }.width(70)
                }
                .frame(minHeight: 120)
                Chart(t.stats) { s in BarMark(x: .value(L10n.tr("Krok"), s.name), y: .value(L10n.tr("Średnio ms"), s.averageMs)) }
                    .frame(height: 120)
                Chart(t.throughput.map { ThroughputPoint(second: $0.0, count: $0.1) }) { p in
                    LineMark(x: .value("s", p.second), y: .value(L10n.tr("Wykonania/s"), p.count))
                }
                .frame(height: 100)
                if let e = t.stats.compactMap(\.lastError).first { Text(e).font(.uiSecondary).foregroundStyle(.red).lineLimit(2) }
            }
        } else {
            Text(L10n.tr("Wyniki pojawią się po starcie")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func start() {
        guard let conn = connection else { return }
        Task {
            // Kroki mogą zmieniać dane — strażnik zmian jak dla okna SQL (prod potwierdza, tylko do odczytu blokuje).
            do {
                try await workspace.guardModification(test.steps.map(\.sql), connectionID: conn)
            } catch CommandError.cancelledByUser {
                return
            } catch {
                workspace.ui?.showError(error.localizedDescription)
                return
            }
            let t = LoadTester(test, connectionID: conn, in: workspace)
            tester = t
            t.start()
        }
    }

    private func export() {
        guard let t = tester else { return }
        let data = ResultExporter.xlsx([t.exportData()])
        Task { _ = await workspace.ui?.saveFile(suggestedName: L10n.tr("Test obciążenia"), fileExtension: "xlsx", data: data) }
    }
}

struct ThroughputPoint: Identifiable {
    let second: Int
    let count: Int
    var id: Int { second }
}

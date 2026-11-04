import AppKit
import PelikanDB
import PelikanLog
import PelikanWorkspace
import SwiftUI

/// Stan okna raportów wydajności (D217): zapytanie (SQL_ID z zaznaczenia) albo raporty bazy.
@MainActor @Observable
final class PerfReportsModel {
    enum Mode: Equatable { case sql(SQLReportTarget), global }

    let workspace: Workspace
    let connection: UUID
    var mode: Mode
    var license: PerfLicense?
    var availability: SQLAvailability?
    var snapshots: [(id: Int, begin: String, end: String, instance: Int)] = []
    var dbNow = ""
    var dbHourAgo = ""
    var loading = false
    var running = false
    var message = ""
    var selected: PerfReport?
    var request = PerfReportRequest(reportID: "", format: .text)
    /// Wpisany SQL_ID albo hash (zmiana zapytania w oknie).
    var input = ""

    init(workspace: Workspace, connection: UUID, mode: Mode, report: String? = nil) {
        self.workspace = workspace
        self.connection = connection
        self.mode = mode
        if case .sql(let t) = mode { input = Self.text(t.target) }
        if let report, let r = PerfReportCatalog.report(report) { selected = r }
    }

    static func text(_ t: SQLIdentity.Target) -> String {
        switch t {
        case .sqlID(let s): s
        case .hash(let h): String(h)
        }
    }

    var connectionName: String { workspace.connections.connection(connection)?.displayName ?? "" }
    var reports: [PerfReport] { mode == .global ? PerfReportCatalog.globalReports : PerfReportCatalog.sqlReports }

    func session() async throws -> any DatabaseSession { try await workspace.toolSession("perf", connection: connection) }

    /// Licencja, dostępność zapytania (z ustaleniem SQL_ID z hasha albo tekstu), migawki i czas bazy.
    func load() async {
        loading = true
        defer { loading = false }
        message = ""
        do {
            let s = try await session()
            let lic = try await ManagementPacks.license(connection: connection, session: s, in: workspace, invoker: .user, ask: true)
            license = lic
            if let r = try? await s.queryAll("select to_char(sysdate, 'YYYY-MM-DD HH24:MI:SS'), to_char(sysdate - 1/24, 'YYYY-MM-DD HH24:MI:SS') from dual", limit: 1).1.first {
                dbNow = r[0].displayText ?? ""; dbHourAgo = r[1].displayText ?? ""
            }
            snapshots = (try? await ManagementPacks.snapshots(in: s)) ?? []
            if case .sql(var t) = mode {
                var sqlID: String
                switch t.target {
                case .sqlID(let id): sqlID = id
                case .hash(let h):
                    guard let id = try await SQLProbe.resolve(hash: h, in: s, license: lic, major: s.info.server.major) else {
                        message = L10n.tr("Nie znaleziono zapytania o HASH_VALUE \(h) w pamięci kursorów\(lic.diagnostics ? L10n.tr(" ani w AWR") : "")")
                        availability = nil
                        return
                    }
                    sqlID = id
                    t.target = .sqlID(id)
                    mode = .sql(t)
                }
                var a = await SQLProbe.probe(sqlID: sqlID, in: s, license: lic)
                if a.isEmpty, let text = t.statement, let other = await SQLProbe.resolve(text: text, in: s), other != sqlID {
                    sqlID = other
                    t.target = .sqlID(other)
                    t.origin = L10n.tr("polecenie pod kursorem (SQL_ID z pamięci kursorów po tekście)")
                    mode = .sql(t)
                    a = await SQLProbe.probe(sqlID: other, in: s, license: lic)
                }
                availability = a
                input = sqlID
                if a.isEmpty {
                    message = L10n.tr("Zapytania \(sqlID) nie ma już w pamięci kursorów, aktywnych sesjach\(lic.diagnostics ? L10n.tr(", ASH, AWR") : "")\(lic.allows(.tuning) ? L10n.tr(" ani SQL Monitor") : "") — raporty nie mają danych. Sprawdź SQL_ID albo połączenie (\(connectionName)).")
                }
            }
            if selected == nil { selected = statuses.first { $0.available }?.report ?? reports.first }
            if let r = selected { select(r) }
        } catch is CancellationError {
        } catch CommandError.cancelledByUser {
            message = L10n.tr("Anulowano — bez deklaracji licencji dostępne są tylko raporty bez pakietów")
        } catch {
            message = error.localizedDescription
        }
    }

    /// Raporty z informacją o dostępności (licencja, wersja, dane zapytania).
    var statuses: [(report: PerfReport, available: Bool, reason: String?)] {
        if let a = availability, mode != .global { return a.reports() }
        let lic = license ?? .all
        let major = availability?.major ?? 99
        return reports.map { r in
            if !lic.allows(r.need) { return (r, false, L10n.tr("Wymaga licencji \(r.need.displayName)")) }
            if major < r.minMajor { return (r, false, L10n.tr("Wymaga Oracle \(r.minMajor) lub nowszej")) }
            if r.parameters.contains(.snapshots), snapshots.count < 2 { return (r, false, L10n.tr("W AWR są mniej niż dwie migawki")) }
            return (r, true, nil)
        }
    }

    func status(_ r: PerfReport) -> (available: Bool, reason: String?) {
        statuses.first { $0.report.id == r.id }.map { ($0.available, $0.reason) } ?? (false, nil)
    }

    /// Źródła raportu do wyboru (z danymi zapytania i licencją).
    func sources(_ r: PerfReport) -> [ReportSource] {
        guard !r.sources.isEmpty else { return [] }
        if let a = availability, mode != .global {
            var s = a.sources(for: r)
            if s.contains(.ashBoth) { s.removeAll { $0 == .ashBoth }; s.insert(.ashBoth, at: 0) }
            return s
        }
        let lic = license ?? .all
        return r.sources.filter { lic.allows($0.need) }
    }

    /// Wartości domyślne parametrów raportu.
    func select(_ r: PerfReport) {
        selected = r
        var q = PerfReportRequest(reportID: r.id, sqlID: availability?.sqlID, format: r.formats.first ?? .text)
        q.source = sources(r).first
        q.instance = availability?.instance ?? snapshots.last?.instance
        if let a = availability, mode != .global {
            if let range = a.snapshotRange { q.beginSnap = range.begin; q.endSnap = range.end }
            let w = a.window(for: q.source)
            q.begin = w.begin.isEmpty ? dbHourAgo : w.begin
            q.end = w.end.isEmpty || w.end <= q.begin ?? "" ? dbNow : w.end
            if q.end ?? "" <= q.begin ?? "" { q.begin = dbHourAgo; q.end = dbNow }
            q.execution = a.executions.first
            q.storedReportID = a.storedReports.first?.reportID
            if q.source == .awr, a.sources.contains(.cursorCache) == false { q.planHash = nil }
        } else {
            if snapshots.count >= 2 { q.beginSnap = snapshots[snapshots.count - 2].id; q.endSnap = snapshots.last!.id }
            if snapshots.count >= 4, let b = q.beginSnap, let e = q.endSnap {
                let len = e - b
                q.endSnap2 = b; q.beginSnap2 = b - max(1, len)
                // Porównanie: wcześniejszy okres jako bazowy.
                swap(&q.beginSnap, &q.beginSnap2); swap(&q.endSnap, &q.endSnap2)
            }
            q.begin = dbHourAgo; q.end = dbNow
            q.realtime = snapshots.count < 2
        }
        if r.id == "sql.planCursor" { q.planFormat = "ALLSTATS LAST +PEEKED_BINDS" }
        if r.id == "sql.planAWR" { q.planFormat = "TYPICAL +PEEKED_BINDS" }
        request = q
    }

    func run() async {
        guard let r = selected, !running else { return }
        running = true
        defer { running = false }
        message = L10n.tr("Generowanie: \(r.title)…")
        do {
            let s = try await session()
            let out = try await PerfReportRunner.run(request, availability: availability, in: s)
            Log.tools.info("Raport wydajności: \(r.id, privacy: .public), format \(out.format.rawValue, privacy: .public)")
            message = L10n.tr("Gotowe: \(out.title)")
            PerfReportPresenter.present(out)
        } catch {
            message = error.localizedDescription
        }
    }
}

/// Okno raportów wydajności.
struct PerfReportsView: View {
    @Bindable var model: PerfReportsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HSplitView {
                reportList.frame(minWidth: 230, idealWidth: 280, maxWidth: 360)
                ScrollView { form.padding(.trailing, 8) }.frame(minWidth: 380)
            }
            HStack {
                if model.loading || model.running { ProgressView().controlSize(.small) }
                Text(model.message).font(.uiSecondary).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled)
                Spacer()
                Button(L10n.tr("Uruchom raport")) { Task { await model.run() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selected.map { !model.status($0).available } ?? true || model.running || model.loading)
            }
        }
        .padding(10)
        .frame(minWidth: 680, minHeight: 460)
        .task { await model.load() }
    }

    @ViewBuilder private var header: some View {
        if case .sql(let t) = model.mode {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField(L10n.tr("SQL_ID albo HASH_VALUE"), text: $model.input)
                        .textFieldStyle(.roundedBorder).font(.code).frame(width: 170)
                        .onSubmit { reload() }
                    Button(L10n.tr("Sprawdź")) { reload() }.disabled(SQLIdentity.parse(model.input) == nil || model.loading)
                    if let h = model.availability?.hashValue { Text("HASH_VALUE \(String(h))").font(.uiSecondary).foregroundStyle(.secondary).textSelection(.enabled) }
                    Spacer()
                    Text(L10n.tr("Połączenie: \(model.connectionName)")).font(.uiSecondary).foregroundStyle(.secondary)
                }
                Text(L10n.tr("Skąd: \(t.origin)")).font(.uiSecondary).foregroundStyle(.secondary)
                if let a = model.availability { AvailabilityStrip(a: a) }
                if let text = model.availability?.text ?? t.statement {
                    DisclosureGroup(L10n.tr("Tekst zapytania\(model.availability?.schema.map { L10n.tr(" (schemat \($0))") } ?? "")")) {
                        CodePreview(text: text).frame(height: 140)
                    }
                    .font(.uiSecondary)
                }
            }
        } else {
            HStack {
                Text(L10n.tr("Raporty wydajności bazy")).font(.uiHeadline)
                Spacer()
                Text(L10n.tr("Połączenie: \(model.connectionName)")).font(.uiSecondary).foregroundStyle(.secondary)
            }
        }
    }

    private func reload() {
        guard let t = SQLIdentity.parse(model.input) else { return }
        model.mode = .sql(SQLReportTarget(target: t, origin: L10n.tr("wpisany"), connection: model.connection))
        model.availability = nil
        Task { await model.load() }
    }

    private var groups: [String] {
        var out: [String] = []
        for r in model.reports where !out.contains(r.group) { out.append(r.group) }
        return out
    }

    private var reportList: some View {
        List(selection: Binding(get: { model.selected?.id }, set: { id in if let id, let r = PerfReportCatalog.report(id) { model.select(r) } })) {
            ForEach(groups, id: \.self) { g in
                Section(g) {
                    ForEach(model.reports.filter { $0.group == g }) { r in
                        let st = model.status(r)
                        HStack(spacing: 6) {
                            Image(systemName: st.available ? "doc.text.magnifyingglass" : "lock")
                                .foregroundStyle(st.available ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.title).foregroundStyle(st.available ? .primary : .secondary)
                                if let reason = st.reason { Text(reason).font(.uiSecondary).foregroundStyle(.secondary).lineLimit(2) }
                            }
                        }
                        .tag(r.id)
                        .help(r.summary)
                        .onTapGesture(count: 2) {
                            model.select(r)
                            if st.available { Task { await model.run() } }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var form: some View {
        if let r = model.selected {
            let st = model.status(r)
            VStack(alignment: .leading, spacing: 10) {
                Text(r.title).font(.uiHeadline)
                Text(r.summary).fixedSize(horizontal: false, vertical: true)
                Text("\(r.api) · \(r.need.displayName)\(r.minMajor > 11 ? " · Oracle \(r.minMajor)+" : "")").font(.uiSecondary).foregroundStyle(.secondary)
                if let n = r.note { Label(n, systemImage: "info.circle").font(.uiSecondary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                if let reason = st.reason { Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                Form { PerfReportParameters(model: model, report: r) }
                    .formStyle(.grouped)
                    .disabled(!st.available)
            }
        } else {
            Text(L10n.tr("Wybierz raport")).foregroundStyle(.secondary)
        }
    }
}

/// Podsumowanie dostępności zapytania (źródła i bindy).
struct AvailabilityStrip: View {
    let a: SQLAvailability

    var body: some View {
        let items = entries
        VStack(alignment: .leading, spacing: 2) {
            FlowRow(items.map(\.0), present: items.map(\.1))
            ForEach(a.notes, id: \.self) { Text($0).font(.uiSecondary).foregroundStyle(.orange) }
        }
    }

    private var entries: [(String, Bool)] {
        var out: [(String, Bool)] = []
        out.append((a.cursors.isEmpty ? L10n.tr("Pamięć kursorów: brak") : L10n.tr("Pamięć kursorów: \(a.cursors.count) kursor(y), plany \(Set(a.cursors.map(\.planHash)).sorted().joined(separator: ", "))"), !a.cursors.isEmpty))
        out.append((L10n.tr("Aktywne sesje: \(a.activeSessions)"), a.activeSessions > 0))
        if a.license.diagnostics {
            out.append((a.ash.map { L10n.tr("ASH: \($0.first) – \($0.last) (\($0.samples) próbek)") } ?? L10n.tr("ASH w pamięci: brak"), a.ash != nil))
            if let lo = a.snapshots.first, let hi = a.snapshots.last {
                out.append((L10n.tr("AWR: migawki \(lo.snapID)–\(hi.snapID) (\(Set(a.snapshots.map(\.snapID)).count))"), true))
            } else { out.append((L10n.tr("AWR: brak"), false)) }
        }
        if a.license.allows(.tuning) {
            out.append((L10n.tr("SQL Monitor: \(a.executions.count) wykonań"), !a.executions.isEmpty))
            if a.major >= 12 { out.append((L10n.tr("Zapisane raporty: \(a.storedReports.count)"), !a.storedReports.isEmpty)) }
        }
        out.append((L10n.tr("Bindy: \(a.bindSets.count) zestaw(y)"), !a.bindSets.isEmpty))
        return out
    }
}

/// Etykiety zawijane do szerokości okna.
struct FlowRow: View {
    let texts: [String]
    let present: [Bool]
    init(_ texts: [String], present: [Bool]) { self.texts = texts; self.present = present }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 4) { chips }
    }

    @ViewBuilder private var chips: some View {
        ForEach(texts.indices, id: \.self) { i in
            Label(texts[i], systemImage: present[i] ? "checkmark.circle.fill" : "circle.dashed")
                .font(.uiSecondary)
                .foregroundStyle(present[i] ? Color.primary : Color.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(present[i] ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08)))
                .lineLimit(1)
        }
    }
}

/// Parametry raportu: źródło, format i wartości raportu, z domyślnymi z dostępności zapytania.
struct PerfReportParameters: View {
    @Bindable var model: PerfReportsModel
    let report: PerfReport

    static let planFormats = ["ALLSTATS LAST +PEEKED_BINDS", "TYPICAL +PEEKED_BINDS", "ALL +PEEKED_BINDS", "ADVANCED", "TYPICAL", "BASIC"]

    var body: some View {
        let sources = model.sources(report)
        if !sources.isEmpty {
            Picker(L10n.tr("Źródło danych"), selection: Binding(get: { model.request.source }, set: { s in
                model.request.source = s
                if let a = model.availability, s != nil {
                    let w = a.window(for: s)
                    if !w.begin.isEmpty, w.begin < (w.end.isEmpty ? model.dbNow : w.end) { model.request.begin = w.begin; model.request.end = w.end.isEmpty ? model.dbNow : w.end }
                }
            })) {
                ForEach(sources, id: \.self) { Text($0.displayName).tag(Optional($0)) }
            }
        } else if !report.sources.isEmpty, model.mode != .global {
            Text(L10n.tr("Zapytania nie ma w żadnym ze źródeł tego raportu")).foregroundStyle(.orange)
        }
        Picker(L10n.tr("Format wyniku"), selection: $model.request.format) {
            ForEach(report.formats, id: \.self) { Text($0.displayName).tag($0) }
        }
        ForEach(report.parameters, id: \.self) { p in parameter(p) }
    }

    @ViewBuilder private func parameter(_ p: ReportParameter) -> some View {
        switch p {
        case .snapshots:
            if report.id != "sql.tuning" || model.request.source == .awr { snapshotPickers(L10n.tr("Migawki AWR"), \.beginSnap, \.endSnap) }
        case .snapshots2:
            snapshotPickers(L10n.tr("Okres do porównania"), \.beginSnap2, \.endSnap2)
        case .timeWindow:
            HStack {
                TextField(L10n.tr("Od"), text: Binding(get: { model.request.begin ?? "" }, set: { model.request.begin = $0 })).font(.code)
                TextField(L10n.tr("Do"), text: Binding(get: { model.request.end ?? "" }, set: { model.request.end = $0 })).font(.code)
                Menu(L10n.tr("Okres")) {
                    Button(L10n.tr("Ostatnia godzina")) { model.request.begin = model.dbHourAgo; model.request.end = model.dbNow }
                    if let a = model.availability {
                        let w = a.window(for: model.request.source)
                        if !w.begin.isEmpty { Button(L10n.tr("Dane zapytania: \(w.begin) – \(w.end.isEmpty ? model.dbNow : w.end)")) { model.request.begin = w.begin; model.request.end = w.end.isEmpty ? model.dbNow : w.end } }
                    }
                    ForEach(model.snapshots.suffix(12).reversed(), id: \.id) { s in
                        Button(L10n.tr("Migawka \(s.id): \(s.begin) – \(s.end)")) { model.request.begin = s.begin; model.request.end = s.end }
                    }
                }
                .fixedSize()
            }
            Text(L10n.tr("Czas bazy, YYYY-MM-DD HH24:MI:SS")).font(.uiSecondary).foregroundStyle(.secondary)
        case .execution:
            if model.request.source == .reportRepository {
                Picker(L10n.tr("Zapisany raport"), selection: Binding(get: { model.request.storedReportID }, set: { model.request.storedReportID = $0 })) {
                    ForEach(model.availability?.storedReports ?? []) { r in Text(L10n.tr("\(r.start) · wykonanie \(r.execID) · raport \(r.reportID)")).tag(Optional(r.reportID)) }
                }
            } else {
                Picker(L10n.tr("Wykonanie"), selection: Binding(get: { model.request.execution }, set: { model.request.execution = $0 })) {
                    ForEach(model.availability?.executions ?? []) { e in
                        Text(L10n.tr("\(e.start) · \(e.status) · \(e.elapsedSeconds) s · wykonanie \(e.execID) · instancja \(e.instance)")).tag(Optional(e))
                    }
                }
            }
        case .planHash:
            if report.id != "sql.tuning" || model.request.bindSet == nil {
                Picker(L10n.tr("Plan (PLAN_HASH_VALUE)"), selection: Binding(get: { model.request.planHash }, set: { model.request.planHash = $0 })) {
                    Text(L10n.tr("Wszystkie")).tag(String?.none)
                    ForEach(model.availability?.planHashes ?? [], id: \.self) { Text($0).tag(Optional($0)) }
                }
            }
        case .child:
            Picker(L10n.tr("Kursor potomny"), selection: Binding(get: { model.request.child }, set: { model.request.child = $0 })) {
                Text(L10n.tr("Wszystkie")).tag(Int?.none)
                ForEach(model.availability?.cursors ?? []) { c in Text(L10n.tr("\(c.child) · plan \(c.planHash) · wykonań \(c.executions)")).tag(Optional(c.child)) }
            }
        case .planFormat:
            Picker(L10n.tr("Format planu (DBMS_XPLAN)"), selection: $model.request.planFormat) {
                ForEach(Self.planFormats, id: \.self) { Text($0).tag($0) }
            }
        case .binds:
            bindChoice
        case .timeLimit:
            Stepper(L10n.tr("Limit czasu doradcy: \(model.request.timeLimit) s"), value: $model.request.timeLimit, in: 10...3600, step: 30)
        case .session:
            HStack {
                TextField("SID", value: $model.request.sid, format: .number.grouping(.never))
                TextField("SERIAL#", value: $model.request.serial, format: .number.grouping(.never))
                TextField(L10n.tr("Instancja"), value: $model.request.instance, format: .number.grouping(.never))
            }
            Text(L10n.tr("Puste SID — sesja narzędzia Pelikana")).font(.uiSecondary).foregroundStyle(.secondary)
        case .days:
            Stepper(L10n.tr("Ostatnie dni: \(model.request.days)"), value: $model.request.days, in: 1...60)
        case .realtime:
            Toggle(L10n.tr("Czas rzeczywisty (dane w pamięci; bez — historia z AWR)"), isOn: $model.request.realtime)
        case .allInstances:
            Toggle(L10n.tr("Wszystkie instancje RAC"), isOn: $model.request.allInstances)
        }
    }

    private func snapshotPickers(_ title: String, _ b: WritableKeyPath<PerfReportRequest, Int?>, _ e: WritableKeyPath<PerfReportRequest, Int?>) -> some View {
        var ids = model.snapshots.map(\.id)
        for v in [model.request[keyPath: b], model.request[keyPath: e]].compactMap({ $0 }) where !ids.contains(v) { ids.append(v) }
        ids.sort()
        let label = { (id: Int) -> String in
            if let s = model.snapshots.first(where: { $0.id == id }) { return "\(id) · \(s.end)" }
            return String(id)
        }
        return Group {
            Picker(L10n.tr("\(title): od"), selection: Binding(get: { model.request[keyPath: b] }, set: { model.request[keyPath: b] = $0 })) {
                ForEach(ids, id: \.self) { Text(label($0)).tag(Optional($0)) }
            }
            Picker(L10n.tr("\(title): do"), selection: Binding(get: { model.request[keyPath: e] }, set: { model.request[keyPath: e] = $0 })) {
                ForEach(ids, id: \.self) { Text(label($0)).tag(Optional($0)) }
            }
        }
    }

    /// Pytanie o użycie zapamiętanych bindów (doradcy): dostępne zestawy z wartościami.
    @ViewBuilder private var bindChoice: some View {
        let sets = (model.availability?.bindSets ?? []).filter(\.usableByAdvisor)
        if sets.isEmpty {
            Text(L10n.tr("Zapamiętanych bindów nie ma — doradca analizuje zapytanie z pamięci kursorów albo AWR")).font(.uiSecondary).foregroundStyle(.secondary)
        } else {
            Picker(L10n.tr("Zapamiętane bindy (\(sets.count) zestaw(y)) — użyć?"), selection: Binding(get: { model.request.bindSet }, set: { model.request.bindSet = $0 })) {
                Text(L10n.tr("Nie — zapytanie z \(model.request.source == .awr ? "AWR" : L10n.tr("pamięci kursorów"))")).tag(SQLAvailability.BindSet?.none)
                ForEach(sets) { s in Text(s.label).tag(Optional(s)) }
            }
            .pickerStyle(.radioGroup)
            if let s = model.request.bindSet {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(s.binds, id: \.position) { b in
                        Text("\(b.position). \(b.name) \(b.type) = \(b.value ?? "NULL")").font(.code).textSelection(.enabled)
                    }
                }
                Text(L10n.tr("Doradca użyje tekstu zapytania z tymi wartościami (sql_text i bind_list).")).font(.uiSecondary).foregroundStyle(.secondary)
            }
        }
    }
}

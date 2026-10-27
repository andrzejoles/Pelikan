import AppKit
import PelikanWorkspace
import SwiftUI
import UniformTypeIdentifiers

/// Widoki dualności JSON (SD-DV-001): lista, dokumenty, struktura i nowy widok z tabel.
struct DualityViewsView: View {
    let workspace: Workspace
    @State private var views: [DualityViews.View] = []
    @State private var selection: DualityViews.View.ID?
    @State private var detail = ""
    @State private var message = ""
    @State private var newName = ""
    @State private var newRoot = ""
    @State private var newChildren = ""

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }.iconLabel(L10n.tr("Odśwież"))
                    Spacer()
                }
                List(views, selection: $selection) { v in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(v.name)
                        Text(L10n.tr("tabela główna \(v.rootTable)")).font(.uiSecondary).foregroundStyle(.secondary)
                    }
                }
                GroupBox(L10n.tr("Nowy widok")) {
                    VStack(alignment: .leading) {
                        TextField(L10n.tr("Nazwa widoku"), text: $newName)
                        TextField(L10n.tr("Tabela główna"), text: $newRoot)
                        TextField(L10n.tr("Tabele podrzędne (po przecinku)"), text: $newChildren)
                        Button(L10n.tr("Generuj DDL")) {
                            workspace.perform("tools.dualityViewDDL", CommandArguments(["name": .string(newName), "root": .string(newRoot), "children": .string(newChildren)]))
                        }.disabled(newName.isEmpty || newRoot.isEmpty)
                    }
                }
            }
            .frame(minWidth: 260)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button(L10n.tr("Dokumenty")) { Task { await documents() } }.disabled(selection == nil)
                    Button(L10n.tr("Struktura")) { Task { await guide() } }.disabled(selection == nil)
                    Spacer()
                    Text(message).font(.uiSecondary).foregroundStyle(.secondary)
                }
                ScrollView([.vertical, .horizontal]) {
                    Text(detail).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .frame(minWidth: 420)
        }
        .padding(10)
        .frame(minWidth: 760, minHeight: 460)
        .task { await reload() }
    }

    private var selected: DualityViews.View? { views.first { $0.id == selection } }

    private func reload() async {
        do {
            let (s, owner) = try await Oracle23Commands.session(workspace)
            views = try await DualityViews.list(owner: owner, in: s)
            message = L10n.tr("Widoki: \(views.count)")
        } catch { message = error.localizedDescription }
    }

    private func documents() async {
        guard let v = selected else { return }
        do {
            let (s, _) = try await Oracle23Commands.session(workspace)
            detail = try await DualityViews.documents(v, in: s).joined(separator: "\n\n")
        } catch { message = error.localizedDescription }
    }

    private func guide() async {
        guard let v = selected else { return }
        do {
            let (s, _) = try await Oracle23Commands.session(workspace)
            detail = try await DualityViews.dataGuide(v, in: s).map { "\($0.path)  \($0.type)" }.joined(separator: "\n")
        } catch { message = error.localizedDescription }
    }
}

/// Moduły i środowiska MLE (SD-MLE-001).
struct MLEModulesView: View {
    let workspace: Workspace
    @State private var modules: [MLE.Module] = []
    @State private var environments: [String] = []
    @State private var selection: MLE.Module.ID?
    @State private var message = ""
    @State private var debugging = false
    @State private var debugLines = ""
    @State private var debugWatch = ""
    @State private var debugCall = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }.iconLabel(L10n.tr("Odśwież"))
                Button(L10n.tr("Importuj plik JavaScript…")) {
                    let p = NSOpenPanel()
                    p.allowedContentTypes = [.javaScript]
                    if p.runModal() == .OK, let url = p.url {
                        workspace.perform("tools.importMLEModule", CommandArguments(["file": .string(url.path)]))
                    }
                }
                Button(L10n.tr("Źródło")) { Task { await openSource() } }.disabled(selection == nil)
                Button(L10n.tr("Debuguj…")) { debugging = true }.disabled(selection == nil)
                Button(L10n.tr("Nowe środowisko")) {
                    let imports = modules.map { "'\($0.name.lowercased())' module \($0.name)" }.joined(separator: ", ")
                    workspace.newDocument(.sql, text: "create or replace mle env NOWE_SRODOWISKO" + (imports.isEmpty ? "" : " imports (\(imports))") + ";\n")
                }
                Spacer()
                Text(message).font(.uiSecondary).foregroundStyle(.secondary)
            }
            Table(modules, selection: $selection) {
                TableColumn(L10n.tr("Moduł"), value: \.name)
                TableColumn(L10n.tr("Język"), value: \.language).width(110)
                TableColumn(L10n.tr("Wersja"), value: \.version).width(80)
            }
            .contextMenu(forSelectionType: MLE.Module.ID.self) { _ in } primaryAction: { _ in Task { await openSource() } }
            Text(L10n.tr("Środowiska: \(environments.isEmpty ? "—" : environments.joined(separator: ", "))")).font(.uiSecondary)
        }
        .padding(10)
        .frame(minWidth: 620, minHeight: 380)
        .task { await reload() }
        .sheet(isPresented: $debugging) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("Debugowanie po wykonaniu: \(modules.first { $0.id == selection }?.name ?? "")")).font(.uiHeadline)
                TextField(L10n.tr("Linie punktów (po przecinku)"), text: $debugLines)
                TextField(L10n.tr("Obserwowane zmienne (puste — wszystkie lokalne)"), text: $debugWatch)
                Text(L10n.tr("Instrukcje PL/SQL wywołujące kod modułu")).font(.uiSecondary)
                CodeTextEditor(text: $debugCall).frame(minHeight: 90)
                HStack {
                    Spacer()
                    Button(L10n.tr("Anuluj"), role: .cancel) { debugging = false }.keyboardShortcut(.cancelAction)
                    Button(L10n.tr("Wykonaj")) {
                        debugging = false
                        guard let m = modules.first(where: { $0.id == selection }) else { return }
                        workspace.perform("tools.debugMLE", CommandArguments(["module": .string(m.name), "lines": .string(debugLines),
                                                                              "watch": .string(debugWatch), "call": .string(debugCall)]))
                    }.disabled(debugLines.isEmpty || debugCall.isEmpty)
                }
            }
            .padding(14)
            .frame(width: 520)
        }
    }

    private func reload() async {
        do {
            let (s, owner) = try await Oracle23Commands.session(workspace)
            modules = try await MLE.modules(owner: owner, in: s)
            environments = try await MLE.environments(owner: owner, in: s)
            message = ""
        } catch { message = error.localizedDescription }
    }

    private func openSource() async {
        guard let m = modules.first(where: { $0.id == selection }) else { return }
        do {
            let (s, _) = try await Oracle23Commands.session(workspace)
            let src = try await MLE.source(owner: m.owner, name: m.name, in: s)
            workspace.newDocument(.program, text: MLE.createModuleDDL(name: m.name, source: src, version: m.version.isEmpty ? nil : m.version) + "\n/\n")
        } catch { message = error.localizedDescription }
    }
}

/// Podgląd geometrii (SD-DATA-001): rysunek przeskalowany do okna i WKT.
struct SpatialPreviewView: View {
    let wkt: [String]
    private var shapes: [Spatial.Shape] { wkt.flatMap(Spatial.parse) }

    var body: some View {
        VSplitView {
            Canvas { ctx, size in
                let pts = shapes.flatMap { $0.parts.flatMap { $0 } }
                guard let minX = pts.map(\.0).min(), let maxX = pts.map(\.0).max(), let minY = pts.map(\.1).min(), let maxY = pts.map(\.1).max() else { return }
                let w = max(maxX - minX, 1e-9), h = max(maxY - minY, 1e-9)
                let k = min((size.width - 20) / w, (size.height - 20) / h)
                func p(_ c: (Double, Double)) -> CGPoint { CGPoint(x: 10 + (c.0 - minX) * k, y: size.height - 10 - (c.1 - minY) * k) }
                for (i, s) in shapes.enumerated() {
                    let color = Color(hue: Double(i % 12) / 12, saturation: 0.6, brightness: 0.8)
                    switch s.kind {
                    case .point:
                        for c in s.parts.flatMap({ $0 }) { ctx.fill(Path(ellipseIn: CGRect(origin: p(c), size: .zero).insetBy(dx: -3, dy: -3)), with: .color(color)) }
                    case .line, .polygon:
                        var path = Path()
                        for part in s.parts where !part.isEmpty {
                            path.move(to: p(part[0]))
                            for c in part.dropFirst() { path.addLine(to: p(c)) }
                            if s.kind == .polygon { path.closeSubpath() }
                        }
                        if s.kind == .polygon { ctx.fill(path, with: .color(color.opacity(0.25)), style: FillStyle(eoFill: true)) }
                        ctx.stroke(path, with: .color(color), lineWidth: 1.5)
                    }
                }
            }
            .frame(minHeight: 260)
            .background(Color(nsColor: .textBackgroundColor))
            ScrollView {
                Text(wkt.joined(separator: "\n")).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minHeight: 80)
        }
        .padding(8)
        .frame(minWidth: 520, minHeight: 420)
    }
}

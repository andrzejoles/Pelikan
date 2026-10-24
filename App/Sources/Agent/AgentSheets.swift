import AppKit
import PelikanAgent
import PelikanWorkspace
import SwiftUI

/// Okno zgody na operację agenta (PROMPT §7.4, Bifold D23): bez przycisku domyślnego (Enter nic nie zatwierdza —
/// użytkownik mógł właśnie pisać w terminalu agenta), „Zatwierdź” aktywny dopiero po 0,8 s, Esc odrzuca.
struct ApprovalView: View {
    let request: ApprovalRequest
    let onDecision: (Bool) -> Void
    @State private var armed = false

    private var preview: EffectPreview { request.preview }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.shield").font(.system(size: 28)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("\(request.agentName) chce wykonać: \(request.title)")).font(.headline)
                    if let c = request.connection {
                        Text(L10n.tr("Połączenie: \(c)")).font(.callout).foregroundStyle(.secondary)
                    }
                    Text(preview.summary).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
            if preview.irreversible {
                Label(L10n.tr("Tej zmiany nie da się cofnąć (COMMIT albo DDL na tabeli) — „Cofnij sesję agenta” jej nie przywróci."),
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.callout.bold())
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !preview.statements.isEmpty {
                        section(L10n.tr("Polecenia")) {
                            Text(preview.statements.joined(separator: "\n\n")).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                    if !preview.affectedObjects.isEmpty {
                        section(L10n.tr("Obiekty, na które wpływa")) {
                            Text(preview.affectedObjects.joined(separator: ", ")).font(.callout).textSelection(.enabled)
                        }
                    }
                    if let rows = preview.estimatedRows {
                        section(L10n.tr("Szacowana liczba wierszy")) { Text("\(rows)").font(.callout.monospacedDigit()) }
                    }
                    if let plan = preview.plan, !plan.isEmpty {
                        section(L10n.tr("Plan wykonania")) {
                            // Wiersze DBMS_XPLAN są szersze niż okno — przewijanie w poziomie zamiast zawijania.
                            ScrollView(.horizontal) {
                                Text(plan).font(.system(size: 10.5, design: .monospaced)).textSelection(.enabled).fixedSize()
                            }
                        }
                    }
                    let args = request.arguments.values.filter { !$0.key.hasPrefix("__") }
                    if !args.isEmpty {
                        section(L10n.tr("Argumenty")) {
                            Text(JSONValue.object(args).description).font(.system(size: 10.5, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 160, maxHeight: 360)
            HStack {
                Spacer()
                Button(L10n.tr("Odrzuć"), role: .cancel) { onDecision(false) }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.tr("Zatwierdź")) { onDecision(true) }
                    .disabled(!armed)
            }
        }
        .padding(16)
        .frame(width: 640)
        .task {
            try? await Task.sleep(for: .milliseconds(800))
            armed = true
        }
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            content()
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
        }
    }
}

/// Macierz uprawnień przy starcie sesji agenta (PROMPT §7.4): poziom każdego narzędzia można obniżyć dla tej sesji.
struct PermissionMatrixView: View {
    let profileName: String
    @State var rows: [PermissionRow]
    let onFinish: ([CommandID: AgentAccess]?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("Uprawnienia sesji: \(profileName)")).font(.headline)
            Text(L10n.tr("Poziom narzędzia można tylko obniżyć. Poziom połączenia (np. produkcja — Odczyt) nadal obowiązuje."))
                .font(.callout).foregroundStyle(.secondary)
            List {
                ForEach($rows) { $row in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.tool).font(.system(size: 12, design: .monospaced))
                            Text(row.title).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $row.chosen) {
                            ForEach(AgentAccess.allCases.filter { $0 <= row.base }, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                }
            }
            .frame(minHeight: 320)
            HStack {
                Button(L10n.tr("Wszystko tylko do odczytu")) {
                    rows = PermissionMatrix.readOnly(rows)
                }
                Button(L10n.tr("Domyślne")) {
                    for i in rows.indices { rows[i].chosen = rows[i].base }
                }
                Spacer()
                Button(L10n.tr("Anuluj"), role: .cancel) { onFinish(nil) }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("Uruchom")) {
                    onFinish(PermissionMatrix.overrides(rows))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 560, height: 520)
    }
}

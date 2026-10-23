import Foundation
import Testing

/// Audyt dostępności źródeł aplikacji (MAC-A11Y-001): VoiceOver potrzebuje etykiety dla każdego elementu bez tekstu.
/// Statyczny przegląd App/Sources — testy pakietu nie uruchamiają interfejsu (D30).
@Suite("Dostępność: etykiety VoiceOver w źródłach aplikacji")
struct AccessibilityAuditTests {
    static let appSources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../../../App/Sources").standardizedFileURL

    static func files() -> [(name: String, lines: [String])] {
        guard let e = FileManager.default.enumerator(at: appSources, includingPropertiesForKeys: nil) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }.compactMap { u in
            (try? String(contentsOf: u, encoding: .utf8)).map { (u.lastPathComponent, $0.components(separatedBy: "\n")) }
        }
    }

    @Test("Źródła aplikacji są dostępne dla testu")
    func sourcesFound() {
        #expect(Self.files().count > 50)
    }

    @Test("Przycisk albo menu z samą ikoną ma etykietę (.iconLabel / .accessibilityLabel)")
    func iconOnlyControls() {
        var missing: [String] = []
        for (name, lines) in Self.files() {
            for (i, line) in lines.enumerated() {
                guard let r = line.range(of: "label: { Image(systemName:") else { continue }
                // Łańcuch modyfikatorów: reszta linii i kolejne linie zaczynające się od „.”.
                var chain = String(line[r.upperBound...])
                var j = i + 1
                while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).hasPrefix(".") { chain += lines[j]; j += 1 }
                if !chain.contains(".iconLabel(") && !chain.contains(".accessibilityLabel(") { missing.append("\(name):\(i + 1)") }
            }
        }
        #expect(missing.isEmpty, "bez etykiety: \(missing.joined(separator: ", "))")
    }

    @Test("Przycisk AppKit z obrazkiem ma opis dostępności")
    func appKitImageButtons() {
        var missing: [String] = []
        for (name, lines) in Self.files() {
            for (i, line) in lines.enumerated() where line.contains("systemSymbolName:") && line.contains("NSButton(") {
                if line.contains("accessibilityDescription: nil") || !line.contains("accessibilityDescription:") { missing.append("\(name):\(i + 1)") }
            }
        }
        #expect(missing.isEmpty, "bez opisu: \(missing.joined(separator: ", "))")
    }

    @Test("Tabele i drzewa AppKit mają etykietę dostępności")
    func tablesAndOutlines() {
        var missing: [String] = []
        let declaration = /(?:let|var)\s+(\w+)\s*=\s*(?:NSTableView|NSOutlineView|GridTableView)\(\)/
        for (name, lines) in Self.files() {
            let text = lines.joined(separator: "\n")
            for m in text.matches(of: declaration) {
                let v = String(m.output.1)
                if !text.contains("\(v).setAccessibilityLabel(") { missing.append("\(name): \(v)") }
            }
        }
        #expect(missing.isEmpty, "bez etykiety: \(missing.joined(separator: ", "))")
    }
}

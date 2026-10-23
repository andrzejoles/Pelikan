import Foundation
@testable import PelikanWorkspace
import Testing

@Suite("Teksty interfejsu: klucze i podstawianie")
struct L10nTests {
    @Test("Klucz jak w scripts/l10n.py: interpolacja → %@, % → %%")
    func keys() {
        let n = 3, name = "EMP"
        let k: L10n.Key = "Tabela \(name): \(n) kolumn, 50 % wypełnienia"
        #expect(k.format == "Tabela %@: %@ kolumn, 50 %% wypełnienia" && k.arguments == ["EMP", "3"])
        let plain: L10n.Key = "Filtr nazw obiektów z %"
        #expect(plain.format == "Filtr nazw obiektów z %%" && plain.arguments.isEmpty)
        let nested: L10n.Key = "Wymaga \(n > 1 ? "Tuning Pack" : "Diagnostics Pack")"
        #expect(nested.format == "Wymaga %@" && nested.arguments == ["Tuning Pack"])
    }

    @Test("Podstawianie: kolejno, pozycyjnie, %% i błędne specyfikatory bez awarii")
    func fill() {
        #expect(L10n.fill("Tabela %@: %@ kolumn, 50 %% wypełnienia", ["EMP", "3"]) == "Tabela EMP: 3 kolumn, 50 % wypełnienia")
        #expect(L10n.fill("%2$@ columns in table %1$@", ["EMP", "3"]) == "3 columns in table EMP")
        #expect(L10n.fill("%@ %@ %@", ["a"]) == "a  ")
        #expect(L10n.fill("100%", []) == "100%" && L10n.fill("%d %s %9$@", ["x"]) == "%d %s ")
        #expect(L10n.tr("Tabela \("EMP"): 100 %") == "Tabela EMP: 100 %")
    }
}

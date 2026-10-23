import Foundation
import PelikanSQL
import Testing

@Suite("Porównanie tekstów")
struct TextDiffTests {
    @Test("Wiersze: wspólne, zmienione z różnicą w linii, usunięte, dodane")
    func rows() {
        let a = "a\nb\nc\nd\ne\n"
        let b = "a\nB2\nc\ne\nf\n"
        let r = TextDiff.rows(a, b)
        #expect(r.map { "\($0.kind)" } == ["same", "changed", "same", "removed", "same", "added"])
        #expect(r[1].left == 2 && r[1].right == 2 && r[1].leftChange == 0..<1 && r[1].rightChange == 0..<2)
        #expect(r[3].left == 4 && r[3].right == nil)
        #expect(r[5].right == 5 && r[5].left == nil)
    }

    @Test("Opcje: wielkość liter, białe znaki, komentarze")
    func options() {
        let a = "select  a from t; -- x\nbegin /* k */ null; end;"
        let b = "SELECT a FROM t;\nbegin null; end;"
        #expect(TextDiff.rows(a, b).contains { $0.kind != .same })
        let o = DiffOptions(ignoreCase: true, ignoreWhitespace: true, ignoreComments: true)
        #expect(TextDiff.rows(a, b, options: o).allSatisfy { $0.kind == .same })
        #expect(TextDiff.rows("x := '--nie komentarz';", "x := '--nie komentarz zmieniony';", options: o).first?.kind == .changed)
    }

    @Test("Unified diff i brak różnic")
    func unified() {
        #expect(TextDiff.unified("a\nb\n", "a\nb\n") == "")
        let u = TextDiff.unified("a\nb\nc\n", "a\nx\nc\n", leftName: "baza", rightName: "plik")
        #expect(u == "--- baza\n+++ plik\n@@ -1,3 +1,3 @@\n a\n-b\n+x\n c\n")
    }

    @Test("Losowe teksty: odtworzenie obu stron z wierszy")
    func randomized() {
        var g = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            let a = (0..<Int.random(in: 0...30, using: &g)).map { _ in String(Int.random(in: 0...5, using: &g)) }
            let b = (0..<Int.random(in: 0...30, using: &g)).map { _ in String(Int.random(in: 0...5, using: &g)) }
            let r = TextDiff.rows(a.joined(separator: "\n"), b.joined(separator: "\n"))
            #expect(r.filter { $0.left != nil }.map(\.leftText) == a)
            #expect(r.filter { $0.right != nil }.map(\.rightText) == b)
        }
    }

    @Test("Wydajność: 50 000 linii z rozproszonymi zmianami")
    func performance() {
        let a = (0..<50_000).map { "linia \($0)" }
        var b = a
        for i in stride(from: 100, to: 50_000, by: 1000) { b[i] = "zmiana \(i)" }
        let clock = ContinuousClock()
        var changed = 0
        let t = clock.measure { changed = TextDiff.rows(a.joined(separator: "\n"), b.joined(separator: "\n")).filter { $0.kind == .changed }.count }
        #expect(changed == 50)
        #expect(t < .seconds(10), "\(t)")
    }
}

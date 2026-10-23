import Foundation
import PelikanSQL
import Testing

@Suite("Pary nawiasów i bloków")
struct PairMatcherTests {
    func at(_ marked: String) -> [String] {
        let o = (marked as NSString).range(of: "|").location
        let text = marked.replacingOccurrences(of: "|", with: "")
        return PairMatcher.pairs(text, offset: o).map { (text as NSString).substring(with: NSRange(location: $0.lowerBound, length: $0.count)) }
    }

    @Test("Nawiasy zagnieżdżone, pominięcie nawiasów w literale")
    func parens() {
        let s = "x := f(a, g(')'), b)|;"
        #expect(at(s) == [")", "("])
        let o = ("x := f(" as NSString).length
        let text = "x := f(a, g(')'), b);"
        #expect(PairMatcher.pairs(text, offset: o).map(\.lowerBound) == [6, 19])
    }

    @Test("BEGIN ↔ END nazwa, IF ↔ END IF, LOOP ↔ END LOOP")
    func blocks() {
        let s = "begin\n  if x then\n    loop null; end loop;\n  end if;\nend p;"
        #expect(at("beg|in\n  if x then\n    loop null; end loop;\n  end if;\nend p;") == ["begin", "end p"])
        #expect(at(s.replacingOccurrences(of: "  if x", with: "  i|f x")) == ["if", "end if"])
        #expect(at(s.replacingOccurrences(of: "end loop", with: "end lo|op")) == ["loop", "end loop"])
        #expect(at("sel|ect 1 from dual").isEmpty)
    }
}

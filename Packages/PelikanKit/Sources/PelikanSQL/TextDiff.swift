import Foundation

/// Opcje porównania (UG 26): ignorowanie wielkości liter, białych znaków i komentarzy SQL.
public struct DiffOptions: Sendable, Hashable, Codable {
    public var ignoreCase = false
    public var ignoreWhitespace = false
    public var ignoreComments = false
    public init(ignoreCase: Bool = false, ignoreWhitespace: Bool = false, ignoreComments: Bool = false) {
        self.ignoreCase = ignoreCase; self.ignoreWhitespace = ignoreWhitespace; self.ignoreComments = ignoreComments
    }
}

/// Wiersz zestawienia dwóch tekstów: linia lewa i/lub prawa (numery od 1) i rodzaj różnicy.
public struct DiffRow: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case same, changed, removed, added }
    public var kind: Kind
    public var left: Int?
    public var right: Int?
    public var leftText: String
    public var rightText: String
    /// Zakresy różniących się znaków w linii (UTF-16) — dla wierszy `changed`.
    public var leftChange: Range<Int>?
    public var rightChange: Range<Int>?
}

/// Porównanie tekstów liniami (najdłuższy wspólny podciąg, algorytm Myersa) z różnicami w obrębie linii.
/// Stan linii względem tekstu bazowego (otwarty albo zapisany): zmieniona albo nowa.
public enum LineChange: Sendable, Hashable { case modified, added }

public enum TextDiff {
    public static func rows(_ a: String, _ b: String, options: DiffOptions = DiffOptions()) -> [DiffRow] {
        let la = lines(a), lb = lines(b)
        let ka = keys(la, options), kb = keys(lb, options)
        let script = myers(ka, kb)
        var out: [DiffRow] = []
        var pendingRemoved: [Int] = []
        var pendingAdded: [Int] = []
        func flush() {
            // Usunięte i dodane obok siebie łączone w pary jako zmienione.
            let n = max(pendingRemoved.count, pendingAdded.count)
            for k in 0..<n {
                let l = k < pendingRemoved.count ? pendingRemoved[k] : nil
                let r = k < pendingAdded.count ? pendingAdded[k] : nil
                if let l, let r {
                    let (cl, cr) = intraline(la[l], lb[r])
                    out.append(DiffRow(kind: .changed, left: l + 1, right: r + 1, leftText: la[l], rightText: lb[r], leftChange: cl, rightChange: cr))
                } else if let l {
                    out.append(DiffRow(kind: .removed, left: l + 1, right: nil, leftText: la[l], rightText: ""))
                } else if let r {
                    out.append(DiffRow(kind: .added, left: nil, right: r + 1, leftText: "", rightText: lb[r]))
                }
            }
            pendingRemoved = []
            pendingAdded = []
        }
        for op in script {
            switch op {
            case .equal(let i, let j):
                flush()
                out.append(DiffRow(kind: .same, left: i + 1, right: j + 1, leftText: la[i], rightText: lb[j]))
            case .delete(let i): pendingRemoved.append(i)
            case .insert(let j): pendingAdded.append(j)
            }
        }
        flush()
        return out
    }

    /// Status linii tekstu względem stanu bazowego (UG 23.12 „Line status”): linie (od 0) zmienione albo nowe.
    public static func lineStatus(baseline: String, current: String) -> [Int: LineChange] {
        guard baseline != current else { return [:] }
        let a = baseline.components(separatedBy: "\n"), b = current.components(separatedBy: "\n")
        // Wspólny początek i koniec pomijane — diff tylko środka (pakiet 50 000 linii z drobną zmianą).
        var p = 0
        while p < a.count, p < b.count, a[p] == b[p] { p += 1 }
        var s = 0
        while s < a.count - p, s < b.count - p, a[a.count - 1 - s] == b[b.count - 1 - s] { s += 1 }
        let ma = Array(a[p..<(a.count - s)]), mb = Array(b[p..<(b.count - s)])
        var out: [Int: LineChange] = [:]
        // Duża zmiana (np. formatowanie całości) — bez kosztownego diffu: cały środek zmieniony.
        if ma.isEmpty || ma.count * mb.count > 4_000_000 {
            for k in mb.indices { out[p + k] = k < ma.count ? .modified : .added }
            return out
        }
        guard !mb.isEmpty else { return out }
        // Końcowy znak nowej linii — puste linie na końcu fragmentu są liniami, nie końcem tekstu.
        for r in rows(ma.joined(separator: "\n") + "\n", mb.joined(separator: "\n") + "\n") {
            guard let line = r.right else { continue }
            switch r.kind {
            case .changed: out[p + line - 1] = .modified
            case .added: out[p + line - 1] = .added
            case .same, .removed: break
            }
        }
        return out
    }

    /// Różnica w formacie unified (dla agenta i schowka).
    public static func unified(_ a: String, _ b: String, leftName: String = "a", rightName: String = "b", options: DiffOptions = DiffOptions(),
                               context: Int = 3) -> String {
        let r = rows(a, b, options: options)
        guard r.contains(where: { $0.kind != .same }) else { return "" }
        var out = "--- \(leftName)\n+++ \(rightName)\n"
        var i = 0
        while i < r.count {
            guard r[i].kind != .same else { i += 1; continue }
            let start = max(0, i - context)
            var end = i
            // Fragment do ostatniej zmiany oddalonej o mniej niż 2× kontekst.
            var k = i
            while k < r.count {
                if r[k].kind != .same { end = k }
                if k - end > 2 * context { break }
                k += 1
            }
            let stop = min(r.count, end + context + 1)
            let slice = r[start..<stop]
            let l0 = slice.compactMap(\.left).first ?? 0, r0 = slice.compactMap(\.right).first ?? 0
            out += "@@ -\(l0),\(slice.filter { $0.left != nil }.count) +\(r0),\(slice.filter { $0.right != nil }.count) @@\n"
            for row in slice {
                switch row.kind {
                case .same: out += " " + row.leftText + "\n"
                case .removed: out += "-" + row.leftText + "\n"
                case .added: out += "+" + row.rightText + "\n"
                case .changed: out += "-" + row.leftText + "\n+" + row.rightText + "\n"
                }
            }
            i = stop
        }
        return out
    }

    static func lines(_ s: String) -> [String] {
        var l = s.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if l.last == "" { l.removeLast() }
        return l
    }

    /// Klucz porównania linii wg opcji.
    static func keys(_ lines: [String], _ o: DiffOptions) -> [String] {
        var inBlock = false
        return lines.map { line in
            var s = line
            if o.ignoreComments { s = stripComments(s, inBlock: &inBlock) }
            if o.ignoreWhitespace { s = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ") }
            if o.ignoreCase { s = s.uppercased() }
            return s
        }
    }

    /// Usunięcie komentarzy SQL z linii (z uwzględnieniem literałów i komentarzy blokowych przez wiele linii).
    static func stripComments(_ line: String, inBlock: inout Bool) -> String {
        var out = ""
        var it = Array(line)
        var i = 0
        var inString = false
        while i < it.count {
            let c = it[i], n: Character? = i + 1 < it.count ? it[i + 1] : nil
            if inBlock {
                if c == "*", n == "/" { inBlock = false; i += 2 } else { i += 1 }
                continue
            }
            if inString {
                out.append(c)
                if c == "'" { inString = false }
                i += 1
                continue
            }
            if c == "'" { inString = true; out.append(c); i += 1; continue }
            if c == "-", n == "-" { break }
            if c == "/", n == "*" { inBlock = true; i += 2; continue }
            out.append(c)
            i += 1
        }
        it = []
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Zakresy różnicy w linii: wspólny początek i koniec (UTF-16).
    static func intraline(_ a: String, _ b: String) -> (Range<Int>, Range<Int>) {
        let x = Array(a.utf16), y = Array(b.utf16)
        var p = 0
        while p < x.count, p < y.count, x[p] == y[p] { p += 1 }
        var s = 0
        while s < x.count - p, s < y.count - p, x[x.count - 1 - s] == y[y.count - 1 - s] { s += 1 }
        return (p..<(x.count - s), p..<(y.count - s))
    }

    enum Op: Equatable { case equal(Int, Int), delete(Int), insert(Int) }

    /// Największa liczba różnic (D) liczona algorytmem Myersa; powyżej — porównanie uproszczone (cały środek między
    /// wspólnym początkiem i końcem jako zmieniony). Ścieżka zajmuje O(D²) pamięci, czas O((N+M)·D).
    static let maxEditDistance = 2000

    /// Algorytm Myersa O((N+M)D) z odtworzeniem ścieżki.
    static func myers(_ a: [String], _ b: [String]) -> [Op] {
        let n = a.count, m = b.count
        if n == 0 { return (0..<m).map { .insert($0) } }
        if m == 0 { return (0..<n).map { .delete($0) } }
        // Wspólny początek i koniec poza algorytmem (typowe porównania wersji źródła).
        var pre = 0
        while pre < n, pre < m, a[pre] == b[pre] { pre += 1 }
        var suf = 0
        while suf < n - pre, suf < m - pre, a[n - 1 - suf] == b[m - 1 - suf] { suf += 1 }
        let A = Array(a[pre..<(n - suf)]), B = Array(b[pre..<(m - suf)])
        let N = A.count, M = B.count
        var ops: [Op] = (0..<pre).map { .equal($0, $0) }
        // Ścieżka: dla każdego d tylko wycinek v[-d…d] (od indeksu d² w `trace`) — tyle potrzebuje odtworzenie.
        let max = N + M
        var v = [Int](repeating: 0, count: 2 * max + 2)
        var trace: [Int] = []
        var last: Int?
        if N > 0, M > 0 {
            outer: for d in 0...Swift.min(max, maxEditDistance) {
                for k in -d...d { trace.append(v[k + max]) }
                for k in stride(from: -d, through: d, by: 2) {
                    var x: Int
                    if k == -d || (k != d && v[k - 1 + max] < v[k + 1 + max]) { x = v[k + 1 + max] } else { x = v[k - 1 + max] + 1 }
                    var y = x - k
                    while x < N, y < M, A[x] == B[y] { x += 1; y += 1 }
                    v[k + max] = x
                    if x >= N, y >= M { last = d; break outer }
                }
            }
        }
        if let last {
            var x = N, y = M
            var back: [Op] = []
            for d in stride(from: last, through: 0, by: -1) {
                func vd(_ k: Int) -> Int { trace[d * d + k + d] }
                let k = x - y
                let prevK = (k == -d || (k != d && vd(k - 1) < vd(k + 1))) ? k + 1 : k - 1
                let prevX = d == 0 ? 0 : vd(prevK)
                let prevY = prevX - prevK
                while x > prevX, y > prevY { back.append(.equal(pre + x - 1, pre + y - 1)); x -= 1; y -= 1 }
                if d > 0 {
                    if x == prevX { back.append(.insert(pre + y - 1)) } else { back.append(.delete(pre + x - 1)) }
                }
                x = prevX
                y = prevY
            }
            ops += back.reversed()
        } else {
            // Bez wspólnej części albo zbyt wiele różnic — środek usunięty i dodany (wiersze łączone w zmienione).
            ops += (0..<N).map { .delete(pre + $0) } + (0..<M).map { .insert(pre + $0) }
        }
        ops += (0..<suf).map { .equal(n - suf + $0, m - suf + $0) }
        return ops
    }
}

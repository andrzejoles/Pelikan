@testable import PelikanWorkspace
import Testing

@Suite("Diagram: punkty łamania linii (PD-DIAG-002)")
struct DiagramBendTests {
    @Test("Dodanie na odcinku z dociąganiem do siatki, przesunięcie, trafienie, usunięcie")
    func bends() throws {
        var d = Diagram()
        let a = d.addNote("A", at: DiagramPoint(0, 0))
        let b = d.addNote("B", at: DiagramPoint(400, 0))
        d.links.append(DiagramLink(kind: .manual, from: a, to: b))
        let pts = try #require(d.polyline(d.links[0]))
        #expect(pts.count == 2)
        let mid = DiagramPoint((pts[0].x + pts[1].x) / 2 + 1, (pts[0].y + pts[1].y) / 2)
        let inserted = d.insertBend(at: mid)
        let hit = try #require(inserted)
        #expect(hit.index == 0 && d.links[0].bends.count == 1)
        #expect(d.links[0].bends[0].x.truncatingRemainder(dividingBy: Diagram.grid) == 0)
        d.moveBend(link: hit.link, index: 0, to: DiagramPoint(203, 157))
        #expect(d.links[0].bends[0] == DiagramPoint(200, 160))
        #expect(d.bend(at: DiagramPoint(202, 158))?.index == 0)
        #expect(d.polyline(d.links[0])?.count == 3)
        // Drugi punkt na odcinku od punktu łamania do celu — wstawiony za pierwszym.
        let p2 = try #require(d.polyline(d.links[0]))
        let added = d.insertBend(at: DiagramPoint((p2[1].x + p2[2].x) / 2, (p2[1].y + p2[2].y) / 2))
        let second = try #require(added)
        #expect(second.index == 1 && d.links[0].bends.count == 2)
        d.removeBend(link: hit.link, index: 0)
        #expect(d.links[0].bends.count == 1)
        #expect(d.link(at: DiagramPoint(-500, -500)) == nil)
    }
}

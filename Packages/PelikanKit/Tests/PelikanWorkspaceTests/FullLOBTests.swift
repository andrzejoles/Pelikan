import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Synchronization
import Testing

/// Sesja z jednym wierszem i LOB-em za lokatorem: `readLOB` oddaje porcje pełnej treści i liczy odczyty.
final class LocatorSession: DatabaseSession, @unchecked Sendable {
    let info = SessionInfo(driver: .instantClient, driverVersion: "fake", clientVersion: "0", server: ServerVersion(major: 23),
                           capabilities: [], currentSchema: "U", sessionUser: "U")
    let text: String?
    let bytes: Data?
    let row: [[OracleValue]]
    let reads = Mutex(0)
    init(text: String? = nil, bytes: Data? = nil, preview: Int) {
        self.text = text; self.bytes = bytes
        let kind: LOBValue.Kind = text != nil ? .clob : .blob
        let length = UInt64(text.map { $0.utf16.count } ?? bytes?.count ?? 0)
        row = [[.lob(LOBValue(kind: kind, text: text.map { String($0.prefix(preview)) }, bytes: bytes?.prefix(preview),
                              length: length, truncated: true, locator: LOBLocator(7)))]]
    }
    func readLOB(_ locator: LOBLocator, offset: UInt64, amount: UInt64) async throws -> LOBValue {
        reads.withLock { $0 += 1 }
        #expect(locator == LOBLocator(7))
        let from = Int(offset - 1)
        if let text {
            let u = Array(text.utf16)
            let part = from < u.count ? String(decoding: u[from ..< min(u.count, from + Int(amount))], as: UTF16.self) : ""
            return LOBValue(kind: .clob, text: part, length: UInt64(u.count), truncated: false)
        }
        let b = bytes ?? Data()
        return LOBValue(kind: .blob, bytes: from < b.count ? b.subdata(in: from ..< min(b.count, from + Int(amount))) : Data(),
                        length: UInt64(b.count), truncated: false)
    }
    func execute(_ sql: String, binds: [BindVariable], options: ExecuteOptions) async throws -> ExecutionResult { ExecutionResult(kind: .other) }
    func fetch(_ resultSet: ResultSetID, maxRows: Int) async throws -> RowBatch { RowBatch(rows: row, hasMore: false) }
    func closeResultSet(_ resultSet: ResultSetID) async {}
    func commit() async throws {}
    func rollback() async throws {}
    func breakExecution() {}
    func ping() async throws {}
    func setTags(_ tags: SessionTags) async throws {}
    func close() async {}
}

@MainActor
@Suite("Pełna wartość LOB z lokatora: panel wartości, Large Data Editor, zapis do pliku")
struct FullLOBTests {
    func grid(_ s: LocatorSession, type: OracleType) async -> ResultGridModel {
        // Zapytanie bez ROWID (złączenie) — dawniej pełna treść była wtedy niedostępna.
        let g = ResultGridModel(columns: [ColumnInfo(name: "DOC", type: type, typeName: type.rawValue)], resultSet: ResultSetID(1),
                                session: s, sql: "select x.doc from a x join b y on y.id = x.id", format: ValueFormat())
        await g.fetchAll()
        return g
    }

    @Test("CLOB obcięty w siatce: pełna treść z lokatora, druga prośba z pamięci; Large Data Editor bez ROWID")
    func clob() async throws {
        let text = String(repeating: "zażółć gęślą jaźń 😀 ", count: 20_000)
        let s = LocatorSession(text: text, preview: 4000)
        let g = await grid(s, type: .clob)
        guard case .lob(let l) = g.value(row: 0, column: 0) else { Issue.record("brak LOB"); return }
        #expect(g.cachedFullLOB(l) == nil)
        let full = try await g.fullLOB(l)
        #expect(full.text == text && !full.truncated)
        let reads = s.reads.withLock { $0 }
        #expect(try await g.fullLOB(l).text == text)
        #expect(s.reads.withLock { $0 } == reads)
        #expect(g.cachedFullLOB(l)?.text == text)
        let m = LargeDataModel(grid: g, row: 0, column: 0)
        #expect(m.truncated)
        try await m.loadFull()
        #expect(m.text == text && !m.truncated)
    }

    @Test("BLOB: zapis do pliku porcjami w całości (bez wcześniejszego pobrania)")
    func blobToFile() async throws {
        let bytes = Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let s = LocatorSession(bytes: bytes, preview: 4000)
        let g = await grid(s, type: .blob)
        guard case .lob(let l) = g.value(row: 0, column: 0) else { Issue.record("brak LOB"); return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-blob-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        try await g.writeLOB(l, to: url)
        #expect(try Data(contentsOf: url) == bytes)
        #expect(s.reads.withLock { $0 } == 3)
        #expect(g.cachedFullLOB(l) == nil)
    }

    @Test("Wartość nieobcięta: bez odczytu z bazy")
    func notTruncated() async throws {
        let s = LocatorSession(text: "abc", preview: 10)
        let l = LOBValue(kind: .clob, text: "abc", length: 3, truncated: false)
        #expect(try await s.fullLOB(l) == l)
        #expect(s.reads.withLock { $0 } == 0)
    }
}

@Suite("Rozpoznanie formatu danych binarnych po sygnaturze (podgląd Quick Look)")
struct BinaryFormatTests {
    @Test("Obrazy, PDF, Office (ZIP), GZIP, stary Office (OLE); nieznane — hex")
    func signatures() {
        func f(_ b: [UInt8]) -> LargeDataFormat { LargeDataFormat.detect(text: nil, bytes: Data(b)) }
        #expect(f([0x49, 0x49, 0x2A, 0x00, 1]) == .tiff)
        #expect(f(Array("RIFF".utf8) + [0, 0, 0, 0] + Array("WEBP".utf8)) == .webp)
        #expect(f([0, 0, 0, 24] + Array("ftypheic".utf8)) == .heic)
        #expect(f([0x1F, 0x8B, 8, 0]) == .gzip)
        let ole: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0]
        #expect(f(ole) == .binary)
        #expect(f(ole + ("Workbook".utf16 + [0]).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }) == .xls)
        #expect(f(ole + ("WordDocument".utf16 + [0]).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }) == .doc)
        #expect(f(Array("BMW zamówienie 123 dla klienta".utf8)) == .text)
        var bmp: [UInt8] = Array("BM".utf8) + [30, 0, 0, 0, 0, 0, 0, 0, 26, 0, 0, 0, 12, 0, 0, 0]
        bmp += [UInt8](repeating: 0, count: 30 - bmp.count)
        #expect(f(bmp) == .bmp)
        #expect(f([0x50, 0x4B, 0x03, 0x04] + Array("password/notes.txt".utf8)) == .zip)
        // BMP ucięty do limitu siatki (rozmiar z nagłówka większy niż pobrane bajty) — nadal BMP.
        var cut = bmp
        cut[2] = 0xFF; cut[3] = 0xFF
        #expect(f(cut) == .bmp)
        // „Book” w treści pliku OLE (nie nazwa strumienia zakończona NUL) — bez zgadywania Excela.
        #expect(f(ole + "Booking".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }) == .binary)
        #expect(f([0x50, 0x4B, 0x03, 0x04] + Array("....[Content_Types].xml....word/document.xml".utf8)) == .docx)
        #expect(f([0x50, 0x4B, 0x03, 0x04] + Array("....[Content_Types].xml....xl/workbook.xml".utf8)) == .xlsx)
        #expect(f([0x50, 0x4B, 0x03, 0x04, 0, 0]) == .zip)
        #expect(f([0x00, 0x01, 0x02, 0xFF]) == .binary)
        #expect(LargeDataFormat.docx.isPreviewable && !LargeDataFormat.binary.isPreviewable && !LargeDataFormat.json.isPreviewable)
        let p = CellValuePresentation.make(.lob(LOBValue(kind: .blob, bytes: Data(Array("%PDF-1.7".utf8)), length: 8, truncated: false)),
                                           column: ColumnInfo(name: "D", type: .blob, typeName: "BLOB"), format: ValueFormat())
        #expect(p.detected == .preview && p.format == .pdf && p.modes.contains(.hex))
    }
}

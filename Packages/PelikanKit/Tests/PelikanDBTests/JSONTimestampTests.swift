import CODPI
import Foundation
import PelikanDB
@testable import PelikanODPI
import Testing

@Suite("Daty w maskach Oracle i w wartościach JSON")
struct JSONTimestampTests {
    @Test("Tekst w cudzysłowie w masce to literał — formatowanie i odczyt")
    func quotedLiteral() {
        let t = OracleTimestamp(year: 2024, month: 5, day: 1, hour: 10, minute: 20, second: 30)
        #expect(t.formatted("YYYY-MM-DD\"T\"HH24:MI:SS") == "2024-05-01T10:20:30")
        #expect(t.formatted("DD \"de\" MON YYYY") == "01 de MAY 2024")
        #expect(OracleTimestamp.parse("01 de MAY 2024", mask: "DD \"de\" MON YYYY") == OracleTimestamp(year: 2024, month: 5, day: 1))
        #expect(OracleTimestamp.parse("2024-05-01T10:20:30", mask: "YYYY-MM-DD\"T\"HH24:MI:SS") == t)
        #expect(OracleTimestamp.parse("01 xx MAY 2024", mask: "DD \"de\" MON YYYY") == nil)
    }

    func json(_ ts: dpiTimestamp, oracleType: Int32 = DPI_ORACLE_TYPE_TIMESTAMP) -> String {
        var buf = dpiDataBuffer()
        buf.asTimestamp = ts
        return withUnsafeMutablePointer(to: &buf) { p in
            ODPISession.jsonText(dpiJsonNode(oracleTypeNum: dpiOracleTypeNum(oracleType), nativeTypeNum: dpiNativeTypeNum(DPI_NATIVE_TYPE_TIMESTAMP), value: p))
        }
    }

    @Test("Data/czas w JSON: ISO 8601 bez cudzysłowów maski, z ułamkiem i strefą, gdy są")
    func jsonTimestamp() {
        #expect(json(dpiTimestamp(year: 2024, month: 5, day: 1, hour: 0, minute: 0, second: 0, fsecond: 0, tzHourOffset: 0, tzMinuteOffset: 0),
                     oracleType: DPI_ORACLE_TYPE_DATE) == "\"2024-05-01T00:00:00\"")
        #expect(json(dpiTimestamp(year: 2024, month: 5, day: 1, hour: 10, minute: 20, second: 30, fsecond: 123_000_000, tzHourOffset: 0, tzMinuteOffset: 0))
                == "\"2024-05-01T10:20:30.123000\"")
        #expect(json(dpiTimestamp(year: 2024, month: 5, day: 1, hour: 10, minute: 20, second: 30, fsecond: 123_456_789, tzHourOffset: 0, tzMinuteOffset: 0))
                == "\"2024-05-01T10:20:30.123456789\"")
        #expect(json(dpiTimestamp(year: 2024, month: 5, day: 1, hour: 10, minute: 20, second: 30, fsecond: 500_000_000, tzHourOffset: 2, tzMinuteOffset: 0))
                == "\"2024-05-01T10:20:30.500000+02:00\"")
        #expect(json(dpiTimestamp(year: 2024, month: 5, day: 1, hour: 10, minute: 20, second: 30, fsecond: 0, tzHourOffset: 0, tzMinuteOffset: -30))
                == "\"2024-05-01T10:20:30-00:30\"")
    }
}

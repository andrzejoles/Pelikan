import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

@Suite("Listy wyboru ustawień (D211) i sortowanie tabel (D212)")
struct ChoicesAndSortingTests {
    @Test("Porównanie komórek: liczby wg wartości, tekst bez wielkości liter, puste na końcu")
    func cellOrder() {
        #expect(CellOrder.compare("9", "10") == .orderedAscending)
        #expect(CellOrder.compare("-5", "3") == .orderedAscending)
        #expect(CellOrder.compare("1,5", "1,25") == .orderedDescending)
        #expect(CellOrder.compare("1 200", "999") == .orderedDescending)
        #expect(CellOrder.compare("abc", "ABD") == .orderedAscending)
        #expect(CellOrder.compare("plik2", "plik10") == .orderedAscending)
        #expect(CellOrder.compare("", "a") == .orderedDescending)
        #expect(CellOrder.number("1e3") == 1000 && CellOrder.number("SYS") == nil && CellOrder.number("12:30") == nil)
        let keys: [SortKey] = [.text("b"), .none, .number(2), .text("a"), .number(1)]
        let sorted = keys.sorted { SortKey.compare($0, $1) == .orderedAscending }
        #expect(sorted == [.number(1), .number(2), .text("a"), .text("b"), .none])
        #expect(Optional<Int>.none.sortKey == .none && Optional(3).sortKey == .number(3) && true.sortKey == .number(1))
    }

    @Test("Pola z listą wartości po przecinku: wybór dopisuje albo usuwa pozycję")
    func toggleList() {
        #expect(PreferenceChoices.toggle("pls", in: "") == "pls")
        #expect(PreferenceChoices.toggle("plb", in: "pls") == "pls, plb")
        #expect(PreferenceChoices.toggle("PLS", in: "pls, plb") == "plb")
        #expect(PreferenceChoices.contains("physical reads", in: "consistent gets,  physical reads"))
        #expect(!PreferenceChoices.contains("reads", in: "physical reads"))
    }

    @Test("Listy wyboru: wartości zgodne z Oracle i bez powtórzeń")
    func catalog() {
        for name in ["NLS_DATE_FORMAT", "NLS_TIMESTAMP_FORMAT", "NLS_NUMERIC_CHARACTERS", "NLS_LANGUAGE", "NLS_TERRITORY", "NLS_SORT", "NLS_COMP"] {
            let c = PreferenceChoices.sessionNLS(name)
            #expect(!c.isEmpty && Set(c.map(\.value)).count == c.count, "\(name)")
        }
        #expect(PreferenceChoices.sessionNLS("NLS_NUMERIC_CHARACTERS").allSatisfy { $0.value.count == 2 })
        // Wartości nie mogą zawierać apostrofu ani średnika — takie wartości kompilator pomija.
        for c in PreferenceChoices.plsqlWarnings + PreferenceChoices.plscope + PreferenceChoices.ccflags {
            #expect(!c.value.contains("'") && !c.value.contains(";"))
        }
        for k in ["parameter", "local", "global", "constant", "cursor", "type"] {
            #expect(PreferenceChoices.naming(k).allSatisfy { $0.value.hasSuffix("_") })
        }
        #expect(PreferenceChoices.webSearches.allSatisfy { $0.value.hasPrefix("https://") && $0.value.contains("%s") })
        #expect(PreferenceChoice("DD-MON-RR", "domyślny").label == "DD-MON-RR — domyślny")
    }

    @Test("Wzorce połączeń i użytkownicy z listy połączeń; hosty z konfiguracji ssh")
    func fromConnections() {
        let a = ConnectionDefinition(target: ConnectionTarget(user: "Scott", connectString: "dev_test"),
                                     sshTunnel: SSHTunnel(host: "bastion", user: "jan"))
        let b = ConnectionDefinition(target: ConnectionTarget(user: "hr", connectString: "dev_pdb"))
        let patterns = PreferenceChoices.connectionPatterns([a, b]).map(\.value)
        #expect(patterns.prefix(2) == ["hr@dev_pdb", "scott@dev_test"])
        #expect(patterns.contains("scott@*") && patterns.contains("*@dev_pdb") && patterns.contains("*@*prod*"))
        #expect(Set(patterns).count == patterns.count)
        #expect(PreferenceChoices.databaseUsers([a, b]).map(\.value) == ["HR", "SCOTT"])

        let config = "Host *\n  User x\nHost bastion jump-1\n  HostName 10.0.0.1\nhost=db?x !bad\nHost  dev_box\n"
        #expect(ConnectionFieldChoices.sshConfigHosts(config) == ["bastion", "jump-1", "dev_box"])
        let c = ConnectionFieldChoices.from([a, b], tnsAliases: ["DEV_TEST", "ORCL"], sshConfig: config, sshKeys: ["~/.ssh/id_ed25519"])
        #expect(c.users.map(\.value) == ["hr", "scott"])
        // Aliasy TNS pierwsze; connect string równy aliasowi (bez wielkości liter) nie powtarza się.
        #expect(c.databases.map(\.value) == ["DEV_TEST", "ORCL", "dev_pdb"])
        #expect(c.sshHosts.map(\.value) == ["bastion", "dev_box", "jump-1"])
        #expect(c.sshKeys.map(\.value) == ["~/.ssh/id_ed25519"])
        #expect(c.editions.first?.value == "ORA$BASE")
    }
}

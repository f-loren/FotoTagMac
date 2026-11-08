import Foundation
import Testing
@testable import FotoTagCore

/// Il profilo di Lorenzo non è nell'app (D54): i test lo leggono dal file che lui importa.
extension Profilo {
    static let fileLorenzo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../profili/esempio-pellicola.json").standardizedFileURL
    static let lorenzo = try! Profilo.importa(fileLorenzo)
}

extension TabellaPellicole {
    static let diLorenzo = Profilo.lorenzo.tabella
}

@Suite struct ProfiliTests {
    func cartella() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("profili-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func fileDiLorenzoSiLegge() {
        #expect(Profilo.lorenzo.id == "lorenzo")
        #expect(Profilo.lorenzo.leggiStrutturaAnno)
        #expect(Profilo.lorenzo.pellicole["p3200"] == "Kodak T-Max P3200")
    }

    @Test func senzaFileCeSoloGenerico() throws {
        let u = try cartella().appendingPathComponent("profili.json")
        #expect(try Profilo.carica(da: u).map(\.id) == ["generico"])
        #expect(try Profilo.carica(da: u)[0].pellicole == TabellaPellicole.comune.nomi)
    }

    @Test func salvaEImportaTornanoUguali() throws {
        let d = try cartella(), u = d.appendingPathComponent("profili.json")
        var tutti = try Profilo.carica(da: u)
        tutti.append(Profilo.lorenzo)
        try Profilo.salva(tutti, in: u)
        #expect(try Profilo.carica(da: u) == tutti)
        let e = d.appendingPathComponent("esportato.json")
        try Profilo.lorenzo.esporta(e)
        #expect(try Profilo.importa(e) == Profilo.lorenzo)
    }

    @Test func vecchiePellicoleVannoAGenerico() throws {
        let d = try cartella()
        try Data(#"{"apx 100": "Agfa APX 100", "_nota": "x"}"#.utf8).write(to: d.appendingPathComponent("pellicole.json"))
        #expect(try Profilo.carica(da: d.appendingPathComponent("profili.json"))[0].pellicole == ["apx 100": "Agfa APX 100"])
    }

    @Test func fileIllegibileMessoDaParte() async throws {
        let d = try cartella(), u = d.appendingPathComponent("profili.json")
        for _ in 0..<2 {   // due volte: la seconda copia non deve cancellare la prima
            try Data("non json".utf8).write(to: u)
            #expect(try Profilo.carica(da: u).map(\.id) == ["generico"])
            try await Task.sleep(for: .seconds(1.1))
        }
        let messi = try FileManager.default.contentsOfDirectory(atPath: d.path).filter { $0.hasPrefix("profili.illeggibile-") }
        #expect(messi.count == 2)
    }

    @Test func campiMancantiPrendonoIlValoreDiPartenza() throws {
        let p = try JSONDecoder().decode(Profilo.self, from: Data(#"{"id": "x", "nome": "Vecchio", "leggiStrutturaAnno": true}"#.utf8))
        #expect(p.pellicole == TabellaPellicole.comune.nomi)
        #expect(p.sottocartelleSaltate.isEmpty)
        #expect(!p.cartellaComeContesto)
    }

    @Test func importaRifiutaSenzaNome() throws {
        let u = try cartella().appendingPathComponent("x.json")
        var p = Profilo.generico; p.nome = " "
        try p.esporta(u)
        #expect(throws: (any Error).self) { try Profilo.importa(u) }
    }
}

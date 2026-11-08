import Foundation
import Testing
@testable import FotoTagCore

@Suite struct CopieTests {
    @Test func tolteSoloLeScrittureOltreICinqueGiorni() throws {
        let radice = FileManager.default.temporaryDirectory.appendingPathComponent("copie-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: radice) }
        let ora = Date()
        for (nome, giorni) in [("vecchia", 6.0), ("recente", 4.0)] {
            let c = radice.appendingPathComponent(nome + "/Volumes/x")
            try FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: c.appendingPathComponent("a.jpg"))
            try FileManager.default.setAttributes([.creationDate: ora.addingTimeInterval(-giorni * 86_400)],
                                                  ofItemAtPath: radice.appendingPathComponent(nome).path)
        }
        #expect(Scrittura.pulisciCopie(in: radice, ora: ora) == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: radice.path) == ["recente"])
        #expect(Scrittura.pulisciCopie(in: radice.appendingPathComponent("manca"), ora: ora) == 0)
    }
}
